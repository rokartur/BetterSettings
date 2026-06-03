//
//  SettingsDetailsSpringAnimator.swift
//  BetterSettings
//
//  One vsync-locked spring drives the "Show Details" subtitle reveal/hide across
//  every visible row at once — the same display-link spring technique the host
//  app's menu panel uses for section expand/collapse, so the motion feels
//  identical (response 0.35, damping 0.8 → smooth with a faint tactile settle).
//
//  Rows self-register a track (subtitle height constraint + label) when the
//  toggle fires; registrations on the same run-loop turn are coalesced into a
//  single CADisplayLink that integrates ONE spring and, in one pass per tick,
//  advances every track's height + opacity and lays out each affected root once.
//  A re-toggle mid-flight retargets in place (spring restarts from 0 with the
//  current velocity carried over) instead of snapping. Core Animation has no
//  spring timing for an Auto Layout constraint constant, hence the manual
//  per-frame integration — exactly what makes the height tween smooth.
//

import AppKit
import QuartzCore

@MainActor
final class SettingsDetailsSpringAnimator {

    static let shared = SettingsDetailsSpringAnimator()

    /// SwiftUI-style spring, matched to the menu panel (response 0.35, damping 0.8).
    static let response: Double = 0.35
    static let damping: Double = 0.8

    private let omega0: Double = 2 * .pi / SettingsDetailsSpringAnimator.response
    private let zeta: Double = SettingsDetailsSpringAnimator.damping

    /// A single row's subtitle tween: height constraint + label opacity, both
    /// driven from `from` to `to` by the shared normalized spring position.
    private final class Track {
        let constraint: NSLayoutConstraint
        weak var label: NSTextField?
        weak var root: NSView?
        var fromHeight: CGFloat
        var toHeight: CGFloat
        var fromAlpha: CGFloat
        var toAlpha: CGFloat
        var onFinish: () -> Void

        init(constraint: NSLayoutConstraint, label: NSTextField?, root: NSView?,
             fromHeight: CGFloat, toHeight: CGFloat, fromAlpha: CGFloat, toAlpha: CGFloat,
             onFinish: @escaping () -> Void) {
            self.constraint = constraint
            self.label = label
            self.root = root
            self.fromHeight = fromHeight
            self.toHeight = toHeight
            self.fromAlpha = fromAlpha
            self.toAlpha = toAlpha
            self.onFinish = onFinish
        }
    }

    private var tracks: [ObjectIdentifier: Track] = [:]

    /// Snapshot taken when a tween starts so the viewport stays visually pinned
    /// while rows above the fold change height (rows below it can move freely).
    private struct ScrollAnchor {
        weak var scrollView: NSScrollView?
        weak var anchorView: NSView?
        let clipOriginY: CGFloat
        let anchorDocumentY: CGFloat
    }
    private var scrollAnchor: ScrollAnchor?

    // Untyped so the property itself stays available on macOS 13; the concrete
    // CADisplayLink is only touched inside `#available(macOS 14, *)` blocks.
    private var displayLink: AnyObject?
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    private var startScheduled = false

    /// Normalized spring position (0 → 1) and velocity.
    private var s: Double = 0
    private var v: Double = 0
    private var isRunning = false

    private init() {}

    // MARK: - Public API

    /// Register (or retarget) a row's subtitle tween. Same-turn calls are
    /// coalesced into one spring; a call while already running retargets every
    /// in-flight track (rebased from its current value, velocity carried).
    func animate(
        constraint: NSLayoutConstraint,
        label: NSTextField?,
        root: NSView?,
        toHeight: CGFloat,
        toAlpha: CGFloat,
        onFinish: @escaping () -> Void
    ) {
        let key = ObjectIdentifier(constraint)
        let fromHeight = constraint.constant
        let fromAlpha = label.map { CGFloat($0.alphaValue) } ?? toAlpha

        if let existing = tracks[key] {
            existing.fromHeight = fromHeight
            existing.toHeight = toHeight
            existing.fromAlpha = fromAlpha
            existing.toAlpha = toAlpha
            existing.label = label
            existing.root = root
            existing.onFinish = onFinish
        } else {
            tracks[key] = Track(
                constraint: constraint, label: label, root: root,
                fromHeight: fromHeight, toHeight: toHeight,
                fromAlpha: fromAlpha, toAlpha: toAlpha, onFinish: onFinish
            )
        }

        if isRunning {
            // Retarget: restart the normalized spring from 0, keep velocity so a
            // direction reversal eases out of its current motion instead of jumping.
            s = 0
            return
        }

        scheduleStart()
    }

    /// Drop a row's track without firing its completion (the row is taking over
    /// its own state, e.g. its subtitle text changed). Stops the clock if empty.
    func cancel(_ constraint: NSLayoutConstraint) {
        tracks.removeValue(forKey: ObjectIdentifier(constraint))
        if tracks.isEmpty { stopClock() }
    }

    // MARK: - Start / coalescing

    private func scheduleStart() {
        guard !startScheduled else { return }
        startScheduled = true
        // Let every row that observes the same notification register first, then
        // start a single spring covering them all.
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    private func start() {
        startScheduled = false
        guard !tracks.isEmpty, !isRunning else { return }

        s = 0
        v = 0
        lastTimestamp = 0
        isRunning = true
        scrollAnchor = captureScrollAnchor()

        if #available(macOS 14.0, *), let view = linkSourceView() {
            let link = view.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            // macOS 13 fallback: a main-run-loop timer integrating in wall-clock time.
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance(to: CACurrentMediaTime()) }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }

    private func linkSourceView() -> NSView? {
        for track in tracks.values {
            if let view = track.root ?? track.label, view.window != nil { return view }
        }
        return nil
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp)
    }

    // MARK: - Integration

    private func advance(to now: CFTimeInterval) {
        if lastTimestamp == 0 { lastTimestamp = now; return }
        var dt = now - lastTimestamp
        lastTimestamp = now
        guard dt > 0 else { return }
        // Clamp dt so a dropped frame / paused app can't make the integrator explode.
        dt = min(max(dt, 1.0 / 240.0), 1.0 / 30.0)

        // Semi-implicit Euler toward equilibrium s = 1.
        let k = omega0 * omega0
        let c = 2 * zeta * omega0
        let a = -k * (s - 1.0) - c * v
        v += a * dt
        s += v * dt

        let settled = abs(s - 1.0) < 0.001 && abs(v) < 0.01
        // Clamp to [0, 1] so a faint spring overshoot never shows a gap or >1 alpha.
        let progress = settled ? 1.0 : max(0.0, min(1.0, s))

        if settled {
            finish()
            return
        }

        applyProgress(CGFloat(progress))
    }

    private func applyProgress(_ p: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for track in tracks.values {
            track.constraint.constant = track.fromHeight + (track.toHeight - track.fromHeight) * p
            track.label?.alphaValue = track.fromAlpha + (track.toAlpha - track.fromAlpha) * p
        }
        layoutRoots()
        applyScrollCompensation()

        CATransaction.commit()
    }

    private func layoutRoots() {
        var laidOut = Set<ObjectIdentifier>()
        for track in tracks.values {
            guard let root = track.root else { continue }
            guard laidOut.insert(ObjectIdentifier(root)).inserted else { continue }
            root.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Finish

    private func finish() {
        let finishing = Array(tracks.values)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for track in finishing {
            track.constraint.constant = track.toHeight
            track.label?.alphaValue = track.toAlpha
        }
        layoutRoots()
        applyScrollCompensation()
        CATransaction.commit()

        stopClock()
        tracks.removeAll()

        for track in finishing { track.onFinish() }
    }

    private func stopClock() {
        if #available(macOS 14.0, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
        timer?.invalidate()
        timer = nil
        isRunning = false
        startScheduled = false
        lastTimestamp = 0
        scrollAnchor = nil
    }

    // MARK: - Scroll-position compensation

    /// Snapshot the clip origin and the first section intersecting the viewport,
    /// so height changes above the fold can be cancelled out and the content
    /// under the user's eyes stays put. Only meaningful when scrolled down.
    private func captureScrollAnchor() -> ScrollAnchor? {
        var scrollView: NSScrollView?
        for track in tracks.values {
            if let found = track.root?.enclosingScrollView {
                scrollView = found
                break
            }
        }
        guard let scrollView, let documentView = scrollView.documentView else { return nil }

        let clipView = scrollView.contentView
        let clipOriginY = clipView.bounds.origin.y
        let visibleRect = clipView.documentVisibleRect
        guard !visibleRect.isEmpty else { return nil }

        let sections: [NSView]
        if let stack = documentView.subviews.first as? NSStackView {
            sections = stack.arrangedSubviews
        } else {
            sections = documentView.subviews
        }

        for section in sections {
            let sectionFrame = section.convert(section.bounds, to: documentView)
            if sectionFrame.maxY > visibleRect.minY {
                return ScrollAnchor(
                    scrollView: scrollView,
                    anchorView: section,
                    clipOriginY: clipOriginY,
                    anchorDocumentY: sectionFrame.origin.y
                )
            }
        }
        return nil
    }

    /// Re-anchor the clip view by however far the captured section has shifted in
    /// document coordinates since the tween began. Called per tick after layout.
    private func applyScrollCompensation() {
        guard let anchor = scrollAnchor,
              let scrollView = anchor.scrollView,
              let documentView = scrollView.documentView,
              let anchorView = anchor.anchorView else { return }

        let newAnchorFrame = anchorView.convert(anchorView.bounds, to: documentView)
        let delta = newAnchorFrame.origin.y - anchor.anchorDocumentY
        guard abs(delta) > 0.5 else { return }

        let clipView = scrollView.contentView
        let newOriginY = anchor.clipOriginY + delta
        let minOriginY = -scrollView.contentInsets.top
        let maxOriginY = max(documentView.frame.height - clipView.bounds.height, minOriginY)
        let clampedOriginY = min(max(newOriginY, minOriginY), maxOriginY)

        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: clampedOriginY))
        scrollView.reflectScrolledClipView(clipView)
    }
}
