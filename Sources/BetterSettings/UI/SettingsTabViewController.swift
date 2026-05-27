//
//  SettingsTabViewController.swift
//  BetterSettings
//
//  Base class every settings tab subclasses. Provides a scrolling, padded
//  vertical stack and helpers to add sections/rows/dividers. Subclasses
//  override `setupContent()`.
//
//  Section anchors and per-control search targets registered here are matched
//  automatically against incoming navigation requests, so search-result jumps
//  (scroll-to + highlight flash) work without any per-subclass code.
//

import AppKit
import QuartzCore

@MainActor
open class SettingsTabViewController: NSViewController {

    // MARK: - Layout constants

    private static let sectionSpacing: CGFloat = 32
    private static let horizontalPadding: CGFloat = 16
    private static let bottomPadding: CGFloat = 20

    // MARK: - Highlight constants

    private static let highlightCornerRadius: CGFloat = 12
    private static let highlightInset: CGFloat = -4
    private static let highlightFillOpacity: CGFloat = 0.14
    private static let highlightStrokeOpacity: CGFloat = 0.44
    private static let highlightStrokeWidth: CGFloat = 1.4
    private static let highlightDelayNanos: UInt64 = 130_000_000
    private static let highlightDurationNanos: UInt64 = 900_000_000
    private static let highlightAnimationDuration: TimeInterval = 0.18

    // MARK: - Views

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.verticalScrollElasticity = .allowed
        sv.horizontalScrollElasticity = .none
        sv.contentView.drawsBackground = false
        return sv
    }()

    /// Top-level content stack. Add sections as arranged subviews.
    public let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsTabViewController.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let documentView: FlippedView = {
        let v = FlippedView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Navigation registries

    private var sectionViewsByAnchor: [String: NSView] = [:]
    private var searchTargetsByItemID: [String: NSView] = [:]

    // MARK: - Highlight state

    private var highlightResetTask: Task<Void, Never>?
    private var pendingHighlightTask: Task<Void, Never>?
    private var highlightOverlayView: SearchHighlightOverlayView?
    private weak var activeHighlightTargetView: NSView?

    private var didSetupContent = false

    // MARK: - Lifecycle

    open override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        scrollView.documentView = documentView
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Self.horizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.horizontalPadding),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -Self.bottomPadding),
        ])

        didSetupContent = true
        setupContent()
    }

    open override func viewWillAppear() {
        super.viewWillAppear()
        scrollToTop(animated: false)
    }

    open override func viewDidDisappear() {
        super.viewDidDisappear()
        removeSearchHighlight()
    }

    // MARK: - Subclass override

    /// Override to populate `contentStack`. Use `addSection`, `addRow`,
    /// `register(section:)`, and `register(searchTarget:)`.
    open func setupContent() {}

    /// Called before the controller is released on window close.
    open func prepareForMemoryRelease() {
        guard isViewLoaded else { return }
        removeSearchHighlight()
        for sub in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        sectionViewsByAnchor.removeAll()
        searchTargetsByItemID.removeAll()
        scrollView.documentView = nil
        view.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Content builders

    /// Adds a section card to the content stack.
    /// - Parameter anchor: When set, registers the section for search/section navigation.
    @discardableResult
    public func addSection(title: String? = nil, anchor: String? = nil) -> SettingsSectionView {
        let section = SettingsSectionView(title: title)
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        if let anchor { sectionViewsByAnchor[anchor] = section }
        return section
    }

    /// Adds a row to a section and optionally registers it as a search target.
    /// - Parameter searchItemID: matches a `SettingsSearchItem.id` so search can
    ///   scroll directly to this control and flash it.
    @discardableResult
    public func addRow(
        to section: SettingsSectionView,
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        accessory: NSView? = nil,
        searchItemID: String? = nil
    ) -> SettingsRowView {
        let row = SettingsRowView(icon: icon, title: title, subtitle: subtitle, accessory: accessory)
        section.addContent(row)
        if let searchItemID { searchTargetsByItemID[searchItemID] = row }
        return row
    }

    public func addDivider(to section: SettingsSectionView) {
        section.addDivider()
    }

    /// Adds an arbitrary full-width view as a top-level section.
    public func addArrangedSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// Manually register a section view for an anchor (for custom layouts).
    public func register(section view: NSView, anchor: String) {
        sectionViewsByAnchor[anchor] = view
    }

    /// Manually register a search target view for a search item id.
    public func register(searchTarget view: NSView, itemID: String) {
        searchTargetsByItemID[itemID] = view
    }

    // MARK: - Navigation

    /// Default handling: resolve the request to a search target or section,
    /// scroll it into view, then flash the highlight. Override for custom needs.
    open func handleNavigationRequest(_ request: SettingsNavigationRequest) {
        view.layoutSubtreeIfNeeded()

        var highlightTarget: NSView?
        if let id = request.searchItemID, let target = searchTargetsByItemID[id], !target.isHidden {
            if !isViewVisible(target) { scrollToView(target, animated: true) }
            highlightTarget = target
        } else if let anchor = request.sectionAnchor, let target = sectionViewsByAnchor[anchor] {
            if !isViewVisible(target) { scrollToView(target, animated: true) }
            highlightTarget = target
        } else {
            scrollToTop(animated: true)
        }

        guard let highlightTarget else {
            removeSearchHighlight()
            return
        }

        pendingHighlightTask?.cancel()
        pendingHighlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.highlightDelayNanos)
            guard let self, !Task.isCancelled else { return }
            self.showSearchHighlight(on: highlightTarget)
        }
    }

    // MARK: - Scrolling

    public func scrollToTop(animated: Bool) {
        let clipView = scrollView.contentView
        let targetOrigin = CGPoint(x: 0, y: -scrollView.contentInsets.top)
        applyScroll(to: targetOrigin, clipView: clipView, animated: animated)
    }

    public func scrollToView(_ targetView: NSView, animated: Bool) {
        view.layoutSubtreeIfNeeded()
        guard targetView.isDescendant(of: documentView) else { return }
        let rectInDocument = documentView.convert(targetView.bounds, from: targetView)
        let toolbarOffset = scrollView.contentInsets.top + 8
        scroll(toY: rectInDocument.minY - toolbarOffset, animated: animated)
    }

    public func isViewVisible(_ targetView: NSView) -> Bool {
        view.layoutSubtreeIfNeeded()
        guard targetView.isDescendant(of: documentView) else { return false }
        let clipView = scrollView.contentView
        let rectInDocument = documentView.convert(targetView.bounds, from: targetView)
        let visibleOriginY = clipView.bounds.origin.y + scrollView.contentInsets.top
        let visibleHeight = clipView.bounds.height - scrollView.contentInsets.top
        let visibleRect = CGRect(x: 0, y: visibleOriginY, width: clipView.bounds.width, height: visibleHeight)
        return visibleRect.contains(rectInDocument)
    }

    private func scroll(toY y: CGFloat, animated: Bool) {
        let clipView = scrollView.contentView
        let minY = -scrollView.contentInsets.top
        let maxY = max(documentView.bounds.height - clipView.bounds.height, 0)
        let clampedY = min(max(y, minY), maxY)
        applyScroll(to: CGPoint(x: 0, y: clampedY), clipView: clipView, animated: animated)
    }

    private func applyScroll(to origin: CGPoint, clipView: NSClipView, animated: Bool) {
        guard animated else {
            clipView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clipView)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(origin)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    // MARK: - Search highlight

    public func showSearchHighlight(on target: NSView) {
        let overlay = highlightOverlay(for: target)
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.highlightAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 1
        }

        highlightResetTask?.cancel()
        highlightResetTask = Task { @MainActor [weak self, weak overlay] in
            try? await Task.sleep(nanoseconds: Self.highlightDurationNanos)
            guard let self, let overlay, !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.highlightAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                overlay.animator().alphaValue = 0
            } completionHandler: { [weak self, weak overlay] in
                MainActor.assumeIsolated {
                    guard let self, let overlay else { return }
                    if self.highlightOverlayView === overlay {
                        self.highlightOverlayView = nil
                        self.activeHighlightTargetView = nil
                    }
                    overlay.removeFromSuperview()
                }
            }
        }
    }

    public func removeSearchHighlight() {
        highlightResetTask?.cancel()
        highlightResetTask = nil
        pendingHighlightTask?.cancel()
        pendingHighlightTask = nil
        highlightOverlayView?.removeFromSuperview()
        highlightOverlayView = nil
        activeHighlightTargetView = nil
    }

    private func highlightOverlay(for target: NSView) -> SearchHighlightOverlayView {
        if let overlay = highlightOverlayView,
           activeHighlightTargetView === target,
           overlay.superview === target {
            return overlay
        }

        highlightResetTask?.cancel()
        highlightOverlayView?.removeFromSuperview()

        let overlay = SearchHighlightOverlayView(
            cornerRadius: Self.highlightCornerRadius,
            fillOpacity: Self.highlightFillOpacity,
            strokeOpacity: Self.highlightStrokeOpacity,
            strokeWidth: Self.highlightStrokeWidth
        )
        target.addSubview(overlay, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: target.topAnchor, constant: Self.highlightInset),
            overlay.leadingAnchor.constraint(equalTo: target.leadingAnchor, constant: Self.highlightInset),
            overlay.trailingAnchor.constraint(equalTo: target.trailingAnchor, constant: -Self.highlightInset),
            overlay.bottomAnchor.constraint(equalTo: target.bottomAnchor, constant: -Self.highlightInset),
        ])
        highlightOverlayView = overlay
        activeHighlightTargetView = target
        return overlay
    }
}

/// Flipped document view so auto-layout content starts at the top-left.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
