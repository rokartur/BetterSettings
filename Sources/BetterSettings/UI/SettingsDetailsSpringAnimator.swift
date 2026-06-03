//
//  SettingsDetailsSpringAnimator.swift
//  BetterSettings
//
//  Vsync-locked spring driving the "Show Details" subtitle reveal/hide across
//  every visible row at once, using the same display-link spring technique as the
//  host app's menu panel so the motion feels consistent.
//
//  Rows self-register a track (subtitle height constraint + label) when the toggle
//  fires; registrations on the same run-loop turn are coalesced under a single
//  CADisplayLink (a 60 Hz Timer below macOS 14). Each track integrates its OWN
//  spring so the duration scales with how far that row travels — a 1-line subtitle
//  snaps quickly while a tall multi-line one glides — which keeps short rows from
//  looking cheap/floaty. The link advances every track and lays out each affected
//  root once per tick; a row finishes (and snaps to its resting state) as soon as
//  its own spring settles. Core Animation has no spring timing for an Auto Layout
//  constraint constant, hence the manual per-frame integration.
//

import AppKit
import QuartzCore

@MainActor
final class SettingsDetailsSpringAnimator {

    static let shared = SettingsDetailsSpringAnimator()

    /// SwiftUI-style spring `response` (period), interpolated by travel distance:
    /// a short subtitle uses `*Short` (snappier) and a tall one `*Long` (fuller),
    /// blended over `referenceTravel` points. Expand is under-damped → it
    /// overshoots the open height and settles (lively). Collapse can't bounce
    /// visibly (its past-0 overshoot is clamped), so it's a touch slower and more
    /// damped → a smooth glide closed. Knobs: raise a `response*` to slow it;
    /// raise a `damping*` toward 1 for less bounce.
    static let responseExpandShort: Double = 0.26
    static let responseExpandLong: Double = 0.45
    static let responseCollapseShort: Double = 0.34
    static let responseCollapseLong: Double = 0.72
    static let dampingExpand: Double = 0.7
    static let dampingCollapse: Double = 0.85
    /// Travel (points) at which a row is considered "tall" and uses the long response.
    static let referenceTravel: CGFloat = 80
    /// Per-row start delay (seconds) so rows cascade top-to-bottom on **expand**
    /// instead of moving in dead unison — identical-height rows looked mechanical
    /// in lockstep. Collapse skips the cascade (all rows close together).
    static let stagger: Double = 0.03
    /// Cap on the cascade so a long tab doesn't ripple for too long.
    static let maxStagger: Double = 0.18

    /// One row's subtitle tween + its own spring state, so each row's timing
    /// scales with its travel distance.
    private final class Track {
        let constraint: NSLayoutConstraint
        weak var label: NSTextField?
        weak var root: NSView?
        var fromHeight: CGFloat
        var toHeight: CGFloat
        var fromAlpha: CGFloat
        var toAlpha: CGFloat
        var onFinish: () -> Void

        var s: Double = 0          // normalized spring position 0 → 1
        var v: Double = 0          // normalized velocity
        var omega0: Double = 0
        var zeta: Double = 0
        var settled = false
        var delay: Double = 0      // seconds to wait before this row starts (cascade)

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

    /// Pick a track's response (scaled by its travel distance) + damping, and
    /// reset its spring. On the animator so it can read the main-actor constants.
    private func configureSpring(_ track: Track) {
        let travel = abs(track.toHeight - track.fromHeight)
        let t = min(1.0, max(0.0, Double(travel / Self.referenceTravel)))
        // Ease the blend (t^1.5) so short rows stay a bit snappier than linear,
        // without making them feel rushed, while tall ones ramp to the long response.
        let tScaled = pow(t, 1.5)
        let response: Double
        if track.toHeight > track.fromHeight + 0.5 {
            response = Self.responseExpandShort + (Self.responseExpandLong - Self.responseExpandShort) * tScaled
            track.zeta = Self.dampingExpand
        } else {
            response = Self.responseCollapseShort + (Self.responseCollapseLong - Self.responseCollapseShort) * tScaled
            track.zeta = Self.dampingCollapse
        }
        track.omega0 = 2 * .pi / response
        track.s = 0
        track.v = 0
        track.settled = false
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
    private var isRunning = false
    private var batchIndex = 0          // running index for assigning cascade delays
    private var elapsed: Double = 0      // seconds since this run started

    private init() {}

    // MARK: - Public API

    /// Register (or retarget) a row's subtitle tween. Same-turn calls are coalesced
    /// under one display link; a call while running re-bases the track from its
    /// current value and restarts that row's spring.
    func animate(
        constraint: NSLayoutConstraint,
        label: NSTextField?,
        root: NSView?,
        toHeight: CGFloat,
        toAlpha: CGFloat,
        onFinish: @escaping () -> Void
    ) {
        // First registration of a fresh batch resets the cascade counter.
        if !isRunning && !startScheduled { batchIndex = 0 }

        let key = ObjectIdentifier(constraint)
        let fromHeight = constraint.constant
        let fromAlpha = label.map { CGFloat($0.alphaValue) } ?? toAlpha

        let track: Track
        let isNew: Bool
        if let existing = tracks[key] {
            track = existing
            isNew = false
        } else {
            track = Track(constraint: constraint, label: label, root: root,
                          fromHeight: fromHeight, toHeight: toHeight,
                          fromAlpha: fromAlpha, toAlpha: toAlpha, onFinish: onFinish)
            tracks[key] = track
            isNew = true
        }
        track.label = label
        track.root = root
        track.fromHeight = fromHeight
        track.toHeight = toHeight
        track.fromAlpha = fromAlpha
        track.toAlpha = toAlpha
        track.onFinish = onFinish
        configureSpring(track)
        // Collapse closes every row in the same instant (no cascade) — hiding
        // details should feel like one motion, not a ripple. Expand still
        // cascades top-to-bottom so identical-height rows don't open in dead unison.
        let isCollapsing = toHeight < fromHeight - 0.5
        if isCollapsing {
            track.delay = 0
        } else if isNew {
            track.delay = min(Double(batchIndex) * Self.stagger, Self.maxStagger)
            batchIndex += 1
        }

        if !isRunning { scheduleStart() }
    }

    /// Drop a row's track without firing its completion (the row is taking over its
    /// own state, e.g. its subtitle text changed). Stops the clock if empty.
    func cancel(_ constraint: NSLayoutConstraint) {
        tracks.removeValue(forKey: ObjectIdentifier(constraint))
        if tracks.isEmpty { stopClock() }
    }

    // MARK: - Start / coalescing

    private func scheduleStart() {
        guard !startScheduled else { return }
        startScheduled = true
        // Let every row that observes the same notification register first, then
        // start a single clock covering them all.
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    private func start() {
        startScheduled = false
        guard !tracks.isEmpty, !isRunning else { return }

        lastTimestamp = 0
        elapsed = 0
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
        elapsed += dt

        // Integrate each row's own spring (semi-implicit Euler toward s = 1), once
        // its cascade delay has elapsed.
        for track in tracks.values where !track.settled {
            guard elapsed >= track.delay else { continue }
            let k = track.omega0 * track.omega0
            let c = 2 * track.zeta * track.omega0
            let a = -k * (track.s - 1.0) - c * track.v
            track.v += a * dt
            track.s += track.v * dt
            track.settled = abs(track.s - 1.0) < 0.001 && abs(track.v) < 0.01
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for track in tracks.values {
            // Height follows the raw spring (overshoot past target on expand),
            // floored at 0 on collapse. Opacity stays clamped to [0, 1].
            let p = track.settled ? 1.0 : track.s
            let pa = track.settled ? 1.0 : max(0.0, min(1.0, track.s))
            let h = track.fromHeight + (track.toHeight - track.fromHeight) * CGFloat(p)
            track.constraint.constant = max(0, h)
            track.label?.alphaValue = track.fromAlpha + (track.toAlpha - track.fromAlpha) * CGFloat(pa)
        }
        layoutRoots()
        applyScrollCompensation()
        CATransaction.commit()

        // Retire rows whose spring has settled; fire their completions (which may
        // hide the subtitle / re-layout), then stop the clock once none remain.
        let settledKeys = tracks.filter { $0.value.settled }.map(\.key)
        var completions: [() -> Void] = []
        for key in settledKeys {
            if let track = tracks.removeValue(forKey: key) { completions.append(track.onFinish) }
        }
        if tracks.isEmpty { stopClock() }
        completions.forEach { $0() }
    }

    private func layoutRoots() {
        var laidOut = Set<ObjectIdentifier>()
        for track in tracks.values {
            guard let root = track.root else { continue }
            guard laidOut.insert(ObjectIdentifier(root)).inserted else { continue }
            root.layoutSubtreeIfNeeded()
        }
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
    /// so height changes above the fold can be cancelled out and the content under
    /// the user's eyes stays put. Only meaningful when scrolled down.
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
