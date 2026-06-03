//
//  SettingsRowView.swift
//  BetterSettings
//
//  Reusable settings row: optional SF Symbol icon + title, optional secondary
//  subtitle, and an arbitrary trailing accessory. Subtitles expand/collapse with
//  the sidebar "Show Details" toggle.
//
//  The subtitle reveal/hide is a single synchronized height + opacity animation.
//  Every visible row receives the same `showDetailsDidChange` notification on the
//  same run-loop turn, so they collapse and expand together in one smooth motion.
//

import AppKit

@MainActor
public final class SettingsRowView: NSView {

    private var titleLabel: NSTextField?
    private var rowStack: NSStackView?
    private var textColumn: NSStackView?
    private var hasSubtitleText = false
    private var subtitleContainerView: NSView?
    private var subtitleLabel: NSTextField?
    private var subtitleHeightConstraint: NSLayoutConstraint?
    private var accessoryView: NSView?
    private var subtitleExpandedHeight: CGFloat = 0
    private var cachedSubtitleMeasurementWidth: CGFloat = 0
    private var cachedSubtitleMeasurementHeight: CGFloat = 0
    private weak var cachedLayoutAnimationRoot: NSView?
    private var fillSuperviewWidthConstraint: NSLayoutConstraint?
    private var isAnimatingSubtitleVisibility = false
    /// Target of the in-flight reveal animation, so a redundant same-direction
    /// toggle is ignored instead of restarting the spring.
    private var animatingTowardVisible: Bool?
    private var hasAppliedInitialSubtitleVisibility = false
    private var pendingSubtitleLayoutResolutionTask: Task<Void, Never>?

    private static let subtitleFallbackWidth: CGFloat = 350
    private static let subtitleHeightEpsilon: CGFloat = 0.5
    private static let subtitleTopSpacing: CGFloat = 2

    // MARK: - Init

    /// Creates a settings row.
    /// - Parameters:
    ///   - icon: Optional SF Symbol name (rendered at 13pt).
    ///   - title: Primary label text (13pt system font).
    ///   - subtitle: Optional secondary text (11pt, secondary color).
    ///   - accessory: Optional trailing view (button, toggle, picker, etc.).
    public init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        accessory: NSView? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setupViews(icon: icon, title: title, subtitle: subtitle, accessory: accessory)
        bindShowDetailsPreference()
        updateSubtitleVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        pendingSubtitleLayoutResolutionTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public override func layout() {
        super.layout()
        refreshSubtitleHeightForCurrentWidthIfNeeded()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        invalidateLayoutAnimationRootCache()
        updateFillSuperviewWidthConstraint()
        scheduleSubtitleLayoutResolutionIfNeeded()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            invalidateLayoutAnimationRootCache()
        }
        updateFillSuperviewWidthConstraint()
        scheduleSubtitleLayoutResolutionIfNeeded()
    }

    public func update(title: String? = nil, subtitle: String? = nil, accessory: NSView?? = nil) {
        if let title {
            titleLabel?.stringValue = title
        }
        if let subtitle {
            updateSubtitleText(subtitle)
        }
        if let accessory {
            updateAccessory(accessory)
        }
    }

    // MARK: - Shared symbol-image cache

    /// Memoizes base SF Symbol images by name across all rows. Symbols are looked
    /// up unconfigured (decorative); each `NSImageView` applies its own size,
    /// weight, and tint. Process-lifetime memo, cleared on window teardown via
    /// `releaseSharedCaches()` (existing views retain their image, so clearing
    /// only affects future builds). Main-actor isolated → no locking needed.
    private static var symbolImageCache: [String: NSImage] = [:]

    private static func cachedSymbolImage(named name: String) -> NSImage? {
        if let cached = symbolImageCache[name] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        symbolImageCache[name] = image
        return image
    }

    /// Drops the shared symbol-image cache. Called on window teardown; the cache
    /// repopulates lazily on the next build.
    static func releaseSharedCaches() {
        symbolImageCache.removeAll(keepingCapacity: false)
    }

    // MARK: - Setup

    private func setupViews(icon: String?, title: String, subtitle: String?, accessory: NSView?) {
        let normalizedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSubtitleText = !(normalizedSubtitle?.isEmpty ?? true)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel = titleLabel

        let textColumn = NSStackView()
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 0
        textColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.addArrangedSubview(titleLabel)
        self.textColumn = textColumn

        if let subtitle = normalizedSubtitle, hasSubtitleText {
            let subtitleContainer = NSView()
            subtitleContainer.translatesAutoresizingMaskIntoConstraints = false
            subtitleContainer.wantsLayer = true
            subtitleContainer.clipsToBounds = true
            subtitleContainer.layerContentsRedrawPolicy = .never
            subtitleContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textColumn.addArrangedSubview(subtitleContainer)
            self.subtitleContainerView = subtitleContainer

            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byWordWrapping
            subtitleLabel.maximumNumberOfLines = 0
            subtitleLabel.preferredMaxLayoutWidth = Self.subtitleFallbackWidth
            subtitleLabel.wantsLayer = true
            subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleContainer.addSubview(subtitleLabel)
            self.subtitleLabel = subtitleLabel
            subtitleExpandedHeight = measuredSubtitleHeight(for: subtitleLabel)
            let subtitleHeightConstraint = subtitleContainer.heightAnchor.constraint(equalToConstant: subtitleExpandedHeight)
            self.subtitleHeightConstraint = subtitleHeightConstraint
            NSLayoutConstraint.activate([
                subtitleHeightConstraint,
                subtitleContainer.widthAnchor.constraint(equalTo: textColumn.widthAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: Self.subtitleTopSpacing),
                subtitleLabel.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            ])
        }

        let hStack = NSStackView()
        hStack.orientation = .horizontal
        hStack.alignment = .top
        hStack.spacing = 6
        hStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack = hStack

        if let icon, !icon.isEmpty {
            let iconView = NSImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            // Shared base symbol image (decorative — the title label carries the
            // a11y label). Size/weight/tint stay per-view, so the image is safe to
            // reuse across rows and across tab rebuilds after an unload.
            iconView.image = Self.cachedSymbolImage(named: icon)
            iconView.contentTintColor = .labelColor
            iconView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
            ])
            hStack.addArrangedSubview(iconView)
        }

        hStack.addArrangedSubview(textColumn)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        hStack.addArrangedSubview(spacer)

        updateAccessory(accessory)

        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAccessory(_ accessory: NSView?) {
        guard let rowStack else { return }

        if let accessoryView {
            rowStack.removeArrangedSubview(accessoryView)
            accessoryView.removeFromSuperview()
            self.accessoryView = nil
        }

        guard let accessory else { return }

        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.setContentHuggingPriority(.required, for: .horizontal)
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        rowStack.addArrangedSubview(accessory)
        accessoryView = accessory
    }

    private func updateSubtitleText(_ subtitle: String) {
        guard let subtitleLabel, let subtitleHeightConstraint else { return }

        let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSubtitleText = !normalizedSubtitle.isEmpty
        subtitleLabel.stringValue = normalizedSubtitle
        invalidateCachedSubtitleMeasurement()

        let shouldShowSubtitle = hasSubtitleText && SettingsDetails.isOn
        let measuredHeight = hasSubtitleText ? measuredSubtitleHeight(for: subtitleLabel) : 0
        if hasSubtitleText {
            subtitleExpandedHeight = measuredHeight
        }

        SettingsDetailsSpringAnimator.shared.cancel(subtitleHeightConstraint)
        isAnimatingSubtitleVisibility = false
        animatingTowardVisible = nil
        performWithoutAnimation {
            subtitleContainerView?.isHidden = !shouldShowSubtitle
            subtitleLabel.isHidden = !shouldShowSubtitle
            subtitleLabel.alphaValue = shouldShowSubtitle ? 1 : 0
            subtitleHeightConstraint.constant = shouldShowSubtitle ? measuredHeight : 0
            layoutContainerIfNeeded()
        }
        scheduleSubtitleLayoutResolutionIfNeeded()
    }

    // MARK: - Show Details binding

    private func bindShowDetailsPreference() {
        guard subtitleLabel != nil else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowDetailsDidChange(_:)),
            name: .betterSettingsShowDetailsDidChange,
            object: nil
        )
    }

    @objc
    private func handleShowDetailsDidChange(_ notification: Notification) {
        updateSubtitleVisibility(shouldShowSubtitle: notification.userInfo?["isOn"] as? Bool)
    }

    /// Reveals or hides the subtitle. The actual motion is a vsync-locked spring
    /// shared across every visible row (`SettingsDetailsSpringAnimator`), so all
    /// rows expand/collapse together with the same smooth, lightly-settling curve
    /// as the host app's menu-panel sections.
    private func updateSubtitleVisibility(shouldShowSubtitle: Bool? = nil) {
        guard hasSubtitleText,
              let subtitleContainerView,
              let subtitleLabel,
              let subtitleHeightConstraint else { return }

        let isInitialSync = !hasAppliedInitialSubtitleVisibility
        hasAppliedInitialSubtitleVisibility = true

        let shouldShow = shouldShowSubtitle ?? SettingsDetails.isOn

        // Already in (or already heading to) the requested state — ignore. This
        // also stops a redundant same-direction toggle from restarting the spring.
        if isAnimatingSubtitleVisibility {
            if animatingTowardVisible == shouldShow { return }
        } else {
            let isSubtitleVisible = !subtitleContainerView.isHidden
                && subtitleHeightConstraint.constant > Self.subtitleHeightEpsilon
            if shouldShow == isSubtitleVisible { return }
        }

        let targetHeight: CGFloat = shouldShow ? measuredSubtitleHeight(for: subtitleLabel) : 0
        if shouldShow {
            subtitleExpandedHeight = targetHeight
        }

        let shouldAnimate = !isInitialSync
            && window != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard shouldAnimate else {
            SettingsDetailsSpringAnimator.shared.cancel(subtitleHeightConstraint)
            isAnimatingSubtitleVisibility = false
            animatingTowardVisible = nil
            // Offscreen/unloaded tabs (window == nil) snap their state but skip the
            // layout flush; they reconcile on their next viewDidMoveToWindow/layout.
            let shouldFlush = window != nil
            performWithoutAnimation {
                subtitleContainerView.isHidden = !shouldShow
                subtitleLabel.isHidden = !shouldShow
                subtitleLabel.alphaValue = shouldShow ? 1 : 0
                subtitleHeightConstraint.constant = targetHeight
                if shouldFlush { layoutContainerIfNeeded() }
            }
            return
        }

        isAnimatingSubtitleVisibility = true
        animatingTowardVisible = shouldShow

        // Keep the subtitle in the tree for the whole tween. The spring rebases
        // from the constraint's current value, so a reversal eases out of its
        // current position instead of snapping to 0 first.
        subtitleContainerView.isHidden = false
        subtitleLabel.isHidden = false

        SettingsDetailsSpringAnimator.shared.animate(
            constraint: subtitleHeightConstraint,
            label: subtitleLabel,
            root: layoutAnimationRoot(),
            toHeight: targetHeight,
            toAlpha: shouldShow ? 1 : 0,
            onFinish: { [weak self] in
                guard let self else { return }
                self.isAnimatingSubtitleVisibility = false
                self.animatingTowardVisible = nil
                guard let subtitleLabel = self.subtitleLabel,
                      let subtitleHeightConstraint = self.subtitleHeightConstraint else { return }
                if shouldShow {
                    subtitleHeightConstraint.constant = self.subtitleExpandedHeight
                    subtitleLabel.alphaValue = 1
                } else {
                    subtitleHeightConstraint.constant = 0
                    subtitleLabel.alphaValue = 0
                    subtitleLabel.isHidden = true
                    self.subtitleContainerView?.isHidden = true
                }
            }
        )
    }

    // MARK: - Subtitle measurement

    private func measuredSubtitleHeight(for subtitleLabel: NSTextField) -> CGFloat {
        let maxWidth = measuredSubtitleWidth(for: subtitleLabel)
        if abs(cachedSubtitleMeasurementWidth - maxWidth) <= Self.subtitleHeightEpsilon,
           cachedSubtitleMeasurementHeight > Self.subtitleHeightEpsilon {
            subtitleLabel.preferredMaxLayoutWidth = maxWidth
            return cachedSubtitleMeasurementHeight
        }

        subtitleLabel.preferredMaxLayoutWidth = maxWidth
        let bounds = subtitleLabel.attributedStringValue.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let measuredHeight = max(1, ceil(bounds.height)) + Self.subtitleTopSpacing
        cachedSubtitleMeasurementWidth = maxWidth
        cachedSubtitleMeasurementHeight = measuredHeight
        return measuredHeight
    }

    private func measuredSubtitleWidth(for subtitleLabel: NSTextField, allowFallback: Bool = true) -> CGFloat {
        if window != nil {
            layoutAnimationRoot().layoutSubtreeIfNeeded()
        }

        // Widest resolved container width — max over candidates > 1, without
        // allocating intermediate arrays/closures (this runs per row per layout).
        var widest: CGFloat = 1
        let superBoundsWidth = subtitleLabel.superview?.bounds.width ?? 0
        if superBoundsWidth > widest { widest = superBoundsWidth }
        let superFrameWidth = subtitleLabel.superview?.frame.width ?? 0
        if superFrameWidth > widest { widest = superFrameWidth }
        let textColumnBoundsWidth = textColumn?.bounds.width ?? 0
        if textColumnBoundsWidth > widest { widest = textColumnBoundsWidth }
        let textColumnFrameWidth = textColumn?.frame.width ?? 0
        if textColumnFrameWidth > widest { widest = textColumnFrameWidth }
        if bounds.width > widest { widest = bounds.width }
        if frame.width > widest { widest = frame.width }
        if widest > 1 { return widest }

        // First valid fallback width, in priority order.
        if subtitleLabel.bounds.width > 1 { return subtitleLabel.bounds.width }
        if subtitleLabel.frame.width > 1 { return subtitleLabel.frame.width }
        if subtitleLabel.preferredMaxLayoutWidth > 1 { return subtitleLabel.preferredMaxLayoutWidth }

        guard allowFallback else { return .zero }
        return max(subtitleLabel.preferredMaxLayoutWidth, Self.subtitleFallbackWidth)
    }

    private func refreshSubtitleHeightForCurrentWidthIfNeeded() {
        guard let subtitleContainerView, let subtitleLabel, let subtitleHeightConstraint else { return }
        guard !isAnimatingSubtitleVisibility else { return }
        guard !subtitleContainerView.isHidden else { return }

        let currentWidth = measuredSubtitleWidth(for: subtitleLabel, allowFallback: window == nil)
        guard currentWidth > 1 else { return }

        guard abs(currentWidth - cachedSubtitleMeasurementWidth) > Self.subtitleHeightEpsilon
              || cachedSubtitleMeasurementHeight <= Self.subtitleHeightEpsilon else {
            return
        }

        let measuredHeight = measuredSubtitleHeight(for: subtitleLabel)
        subtitleExpandedHeight = measuredHeight

        guard abs(subtitleHeightConstraint.constant - measuredHeight) > Self.subtitleHeightEpsilon else { return }

        subtitleHeightConstraint.constant = measuredHeight
    }

    private func invalidateCachedSubtitleMeasurement() {
        cachedSubtitleMeasurementWidth = 0
        cachedSubtitleMeasurementHeight = 0
    }

    /// After the row lands in a window the real column width is known, so the
    /// subtitle height is re-measured once layout settles to avoid clipped text.
    private func scheduleSubtitleLayoutResolutionIfNeeded() {
        guard hasSubtitleText,
              subtitleLabel != nil,
              subtitleHeightConstraint != nil else { return }

        pendingSubtitleLayoutResolutionTask?.cancel()
        pendingSubtitleLayoutResolutionTask = Task { @MainActor [weak self] in
            await Task.yield()

            guard let self,
                  !Task.isCancelled,
                  self.window != nil,
                  let subtitleLabel = self.subtitleLabel,
                  let subtitleHeightConstraint = self.subtitleHeightConstraint else { return }

            self.layoutAnimationRoot().layoutSubtreeIfNeeded()

            let resolvedWidth = self.measuredSubtitleWidth(for: subtitleLabel, allowFallback: false)
            guard resolvedWidth > 1 else { return }

            let widthDidChange = abs(resolvedWidth - self.cachedSubtitleMeasurementWidth) > Self.subtitleHeightEpsilon
                || abs(resolvedWidth - subtitleLabel.preferredMaxLayoutWidth) > Self.subtitleHeightEpsilon
            guard widthDidChange || self.cachedSubtitleMeasurementHeight <= Self.subtitleHeightEpsilon else { return }

            self.invalidateCachedSubtitleMeasurement()
            subtitleLabel.preferredMaxLayoutWidth = resolvedWidth
            let measuredHeight = self.measuredSubtitleHeight(for: subtitleLabel)
            self.subtitleExpandedHeight = measuredHeight

            guard !self.isAnimatingSubtitleVisibility else { return }

            self.performWithoutAnimation {
                subtitleLabel.preferredMaxLayoutWidth = resolvedWidth
                if SettingsDetails.isOn {
                    subtitleHeightConstraint.constant = measuredHeight
                }
                self.layoutContainerIfNeeded()
            }
        }
    }

    // MARK: - Layout helpers

    private func layoutAnimationRoot() -> NSView {
        if let cachedLayoutAnimationRoot {
            return cachedLayoutAnimationRoot
        }

        if let documentView = enclosingScrollView?.documentView {
            cachedLayoutAnimationRoot = documentView
            return documentView
        }

        var root: NSView = self
        while let parent = root.superview, !(parent is NSClipView) {
            root = parent
        }
        cachedLayoutAnimationRoot = root
        return root
    }

    private func layoutContainerIfNeeded() {
        layoutAnimationRoot().layoutSubtreeIfNeeded()
    }

    private func invalidateLayoutAnimationRootCache() {
        cachedLayoutAnimationRoot = nil
    }

    private func updateFillSuperviewWidthConstraint() {
        fillSuperviewWidthConstraint?.isActive = false
        fillSuperviewWidthConstraint = nil

        guard let stackView = superview as? NSStackView, stackView.orientation == .vertical else {
            return
        }

        let constraint = widthAnchor.constraint(equalTo: stackView.widthAnchor)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        fillSuperviewWidthConstraint = constraint
    }

    private func performWithoutAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        updates()
        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }
}
