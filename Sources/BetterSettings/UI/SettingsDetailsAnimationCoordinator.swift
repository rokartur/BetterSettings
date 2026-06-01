//
//  SettingsDetailsAnimationCoordinator.swift
//  BetterSettings
//
//  Coordinates the single "Show Details" toggle animation across every row in
//  the active tab: a two-phase sequence (subtitle fade, then section-height
//  layout transition) run inside one animation group, with scroll-position
//  compensation so the viewport stays visually anchored while sections above
//  the fold change height. Ported 1:1 from the BetterAudio preferences window.
//

import AppKit
import QuartzCore

@MainActor
final class SettingsDetailsAnimationCoordinator {
    enum ToggleAnimationPhase: String {
        case subtitleFade
        case layoutTransition
    }

    static let shared = SettingsDetailsAnimationCoordinator()
    static let subtitleFadeInDelay: TimeInterval = 0.05
    static let subtitleFadeInDuration: TimeInterval = 0.22
    static let subtitleFadeOutDuration: TimeInterval = 0.20
    static let subtitleFadeTiming = CAMediaTimingFunction(controlPoints: 0.24, 0.82, 0.39, 1.0)
    static let sectionExpandDelay: TimeInterval = 0
    static let sectionCollapseDelay: TimeInterval = 0.01
    static let sectionExpandDuration: TimeInterval = 0.32
    static let sectionCollapseDuration: TimeInterval = 0.52
    static let sectionExpandTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.32, 1.0)
    static let sectionCollapseTiming = CAMediaTimingFunction(controlPoints: 0.18, 0.96, 0.52, 1.0)
    static let toggleAnimationDuration: TimeInterval = max(sectionExpandDelay + sectionExpandDuration, sectionCollapseDelay + sectionCollapseDuration)
    static let toggleAnimationTiming = sectionExpandTiming

    static func layoutPhaseDelay(for shouldShowSubtitle: Bool) -> TimeInterval {
        shouldShowSubtitle ? sectionExpandDelay : sectionCollapseDelay
    }

    static func subtitleFadeDuration(for shouldShowSubtitle: Bool) -> TimeInterval {
        shouldShowSubtitle ? subtitleFadeInDuration : subtitleFadeOutDuration
    }

    static func sectionResizeDuration(for shouldShowSubtitle: Bool) -> TimeInterval {
        shouldShowSubtitle ? sectionExpandDuration : sectionCollapseDuration
    }

    static func sectionResizeTiming(for shouldShowSubtitle: Bool) -> CAMediaTimingFunction {
        shouldShowSubtitle ? sectionExpandTiming : sectionCollapseTiming
    }

    private let layoutRoots = NSHashTable<NSView>.weakObjects()
    private weak var activeTabView: NSView?
    private var activeToggleGeneration: UInt = 0
    private var isAnimatingToggleFlag = false
    private var completions: [() -> Void] = []
    private var pendingActiveTabPreparationTask: Task<Void, Never>?

    private init() {}

    func beginToggleAnimation() -> UInt {
        activeToggleGeneration &+= 1
        isAnimatingToggleFlag = true
        layoutRoots.removeAllObjects()
        completions.removeAll(keepingCapacity: true)
        return activeToggleGeneration
    }

    func isAnimatingToggle(generation: UInt?) -> Bool {
        guard let generation else { return false }
        return isAnimatingToggleFlag && generation == activeToggleGeneration
    }

    func setActiveTabView(_ tabView: NSView?) {
        guard activeTabView !== tabView else { return }

        pendingActiveTabPreparationTask?.cancel()
        activeTabView = tabView
        guard let tabView else { return }

        if tabView.window != nil, tabView.superview != nil {
            prepareActiveTabLayoutForAnimation()
            return
        }

        pendingActiveTabPreparationTask = Task { @MainActor [weak self, weak tabView] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  let tabView,
                  self.activeTabView === tabView,
                  tabView.window != nil,
                  tabView.superview != nil else { return }
            self.prepareActiveTabLayoutForAnimation()
        }
    }

    func isViewInActiveTab(_ view: NSView) -> Bool {
        guard let activeTabView else { return false }
        return view === activeTabView || view.isDescendant(of: activeTabView)
    }

    func registerLayoutRoot(_ root: NSView, generation: UInt?) {
        guard isAnimatingToggle(generation: generation) else { return }
        layoutRoots.add(root)
    }

    func registerCompletion(generation: UInt?, _ completion: @escaping () -> Void) {
        guard isAnimatingToggle(generation: generation) else { return }
        completions.append(completion)
    }

    func flushLayouts() {
        prepareActiveTabLayoutForAnimation()
        for root in layoutRoots.allObjects {
            root.layoutSubtreeIfNeeded()
        }
    }

    func finishToggleAnimation(generation: UInt) {
        guard isAnimatingToggle(generation: generation) else { return }
        isAnimatingToggleFlag = false
        let completions = self.completions
        self.completions.removeAll(keepingCapacity: true)
        layoutRoots.removeAllObjects()
        completions.forEach { $0() }
    }

    // MARK: - Scroll position compensation

    /// Snapshot of the scroll state taken before a toggle animation begins, used
    /// to keep the visible content stable when rows above the viewport change height.
    struct ScrollAnchor {
        weak var scrollView: NSScrollView?
        weak var anchorView: NSView?
        let clipOriginY: CGFloat
        let anchorDocumentY: CGFloat
    }

    /// Captures the current scroll position and a reference view (the first
    /// section whose frame intersects the visible viewport). Call **before** any
    /// height changes are applied.
    func captureScrollAnchor() -> ScrollAnchor? {
        guard let activeTabView,
              let scrollView = activeTabView.firstDescendant(ofType: NSScrollView.self),
              let documentView = scrollView.documentView else { return nil }

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

    /// Animates the clip view's bounds origin to keep the visible content at the
    /// same visual position after the anchor shifted. Call **inside** the
    /// animation group, after `flushLayouts()` resolved the final layout.
    func animateScrollCompensation(from anchor: ScrollAnchor?) {
        guard let anchor,
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

        clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedOriginY))
        scrollView.reflectScrolledClipView(clipView)
    }

    func prepareActiveTabLayoutForAnimation() {
        guard let activeTabView else { return }

        var layoutRoots: [NSView] = []

        if let windowContentView = activeTabView.window?.contentView {
            layoutRoots.append(windowContentView)
        }

        var ancestor: NSView? = activeTabView
        while let view = ancestor {
            layoutRoots.append(view)
            ancestor = view.superview
        }

        if let scrollView = activeTabView.firstDescendant(ofType: NSScrollView.self) {
            layoutRoots.append(scrollView)
            layoutRoots.append(scrollView.contentView)
            if let documentView = scrollView.documentView {
                layoutRoots.append(documentView)
            }
        }

        var seen = Set<ObjectIdentifier>()
        for root in layoutRoots {
            let identifier = ObjectIdentifier(root)
            guard seen.insert(identifier).inserted else { continue }
            root.layoutSubtreeIfNeeded()
        }
    }
}

extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let typedSelf = self as? T {
            return typedSelf
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
