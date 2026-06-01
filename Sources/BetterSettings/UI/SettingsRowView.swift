//
//  SettingsRowView.swift
//  BetterSettings
//
//  Reusable settings row: optional SF Symbol icon + title, optional secondary
//  subtitle, and an arbitrary trailing accessory. Subtitles expand/collapse with
//  the sidebar "Show Details" toggle.
//
//  The subtitle show/hide animation (height + alpha + subtle transform, with a
//  shared two-phase toggle driven by `SettingsDetailsAnimationCoordinator`) is a
//  1:1 port of the BetterAudio preferences row so the motion is identical.
//

import AppKit
import QuartzCore

@MainActor
public final class SettingsRowView: NSView {

    private var titleLabel: NSTextField?
    private var rowStack: NSStackView?
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
    private var subtitleAnimationGeneration: UInt = 0
    private var pendingSubtitleLayoutResolutionTask: Task<Void, Never>?
    private var hasAppliedInitialSubtitleVisibility = false
    private static let subtitleShowAnimationMinDuration: TimeInterval = 0.18
    private static let subtitleShowAnimationMaxDuration: TimeInterval = 0.32
    private static let subtitleHideAnimationMinDuration: TimeInterval = 0.18
    private static let subtitleHideAnimationMaxDuration: TimeInterval = 0.30
    private static let subtitleFallbackWidth: CGFloat = 350
    private static let subtitleHeightEpsilon: CGFloat = 0.5
    private static let subtitleAlphaEpsilon: CGFloat = 0.01
    private static let subtitleTopSpacing: CGFloat = 2
    private static let subtitleRevealDelay: TimeInterval = 0.04
    private static let subtitleCollapseLead: TimeInterval = 0.06
    private static let subtitleHiddenScale: CGFloat = 0.985
    private static let subtitleHiddenYOffset: CGFloat = -4
    private static let subtitleTransformAnimationKey = "SettingsRowView.subtitleTransform"
    private static let subtitleHeightAnimationTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.32, 1.0)
    private static let subtitleHideAnimationTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.84, 0.3, 1.0)

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
            subtitleLabel.preferredMaxLayoutWidth = 350
            subtitleLabel.wantsLayer = true
            subtitleLabel.layerContentsRedrawPolicy = .onSetNeedsDisplay
            subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleContainer.addSubview(subtitleLabel)
            self.subtitleLabel = subtitleLabel
            subtitleExpandedHeight = measuredSubtitleHeight(for: subtitleLabel)
            let subtitleHeightConstraint = subtitleContainer.heightAnchor.constraint(equalToConstant: subtitleExpandedHeight)
            subtitleHeightConstraint.isActive = true
            self.subtitleHeightConstraint = subtitleHeightConstraint
            NSLayoutConstraint.activate([
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
            iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
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
        guard let subtitleLabel, let subtitleContainerView, let subtitleHeightConstraint else { return }

        let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSubtitleText = !normalizedSubtitle.isEmpty
        subtitleLabel.stringValue = normalizedSubtitle
        invalidateCachedSubtitleMeasurement()

        guard hasSubtitleText else {
            applySubtitleStateImmediately(height: 0, alpha: 0, isHidden: true, shouldShowSubtitle: false)
            return
        }

        let measuredHeight = measuredSubtitleHeight(for: subtitleLabel)
        subtitleExpandedHeight = measuredHeight
        let shouldShowSubtitle = SettingsDetails.isOn

        performWithoutAnimation {
            subtitleContainerView.isHidden = !shouldShowSubtitle
            subtitleLabel.isHidden = !shouldShowSubtitle
            subtitleLabel.alphaValue = shouldShowSubtitle ? 1 : 0
            subtitleLabel.layer?.transform = shouldShowSubtitle ? CATransform3DIdentity : Self.hiddenSubtitleTransform
            subtitleHeightConstraint.constant = shouldShowSubtitle ? measuredHeight : 0
            updateRowAlignment(shouldShowSubtitle: shouldShowSubtitle)
            layoutContainerIfNeeded()
        }
        scheduleSubtitleLayoutResolutionIfNeeded()
        isAnimatingSubtitleVisibility = false
    }

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
        updateSubtitleVisibility(
            shouldShowSubtitle: notification.userInfo?["isOn"] as? Bool,
            toggleAnimationGeneration: notification.userInfo?["animationGeneration"] as? UInt,
            animationPhase: (notification.userInfo?["animationPhase"] as? String)
                .flatMap(SettingsDetailsAnimationCoordinator.ToggleAnimationPhase.init(rawValue:))
        )
    }

    private func updateSubtitleVisibility(
        shouldShowSubtitle: Bool? = nil,
        toggleAnimationGeneration: UInt? = nil,
        animationPhase: SettingsDetailsAnimationCoordinator.ToggleAnimationPhase? = nil
    ) {
        guard let subtitleContainerView, let subtitleLabel, let subtitleHeightConstraint else {
            updateRowAlignment(shouldShowSubtitle: false)
            return
        }

        let shouldShowSubtitle = shouldShowSubtitle ?? SettingsDetails.isOn
        let isInActiveTab = SettingsDetailsAnimationCoordinator.shared.isViewInActiveTab(self)
        if !isInActiveTab || window == nil {
            hasAppliedInitialSubtitleVisibility = true
            applySubtitleStateForInactiveTab(
                shouldShowSubtitle: shouldShowSubtitle,
                subtitleContainerView: subtitleContainerView,
                subtitleLabel: subtitleLabel,
                subtitleHeightConstraint: subtitleHeightConstraint
            )
            return
        }

        let currentState = synchronizeAnimatedSubtitleStateIfNeeded()
        let isInitialSync = !hasAppliedInitialSubtitleVisibility
        hasAppliedInitialSubtitleVisibility = true
        let targetExpandedHeight = shouldShowSubtitle ? measuredSubtitleHeight(for: subtitleLabel) : 0
        if shouldShowSubtitle {
            subtitleExpandedHeight = targetExpandedHeight
        }

        guard !isSubtitleStateSettled(
            shouldShowSubtitle: shouldShowSubtitle,
            currentState: currentState,
            targetExpandedHeight: targetExpandedHeight,
            subtitleContainerView: subtitleContainerView,
            subtitleLabel: subtitleLabel
        ) else {
            updateRowAlignment(shouldShowSubtitle: shouldShowSubtitle)
            return
        }

        let layoutRoot = layoutAnimationRoot()
        let usesSharedToggleAnimation = SettingsDetailsAnimationCoordinator.shared.isAnimatingToggle(generation: toggleAnimationGeneration)

        if usesSharedToggleAnimation, let animationPhase {
            handleSharedTogglePhase(
                animationPhase,
                shouldShowSubtitle: shouldShowSubtitle,
                currentState: currentState,
                layoutRoot: layoutRoot,
                toggleAnimationGeneration: toggleAnimationGeneration,
                subtitleContainerView: subtitleContainerView,
                subtitleLabel: subtitleLabel,
                subtitleHeightConstraint: subtitleHeightConstraint
            )
            return
        }

        let shouldAnimate = usesSharedToggleAnimation || (!isInitialSync && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        if shouldShowSubtitle {
            updateRowAlignment(shouldShowSubtitle: true)
            subtitleContainerView.isHidden = false
            subtitleLabel.isHidden = false
            let expandedHeight = targetExpandedHeight

            if usesSharedToggleAnimation {
                isAnimatingSubtitleVisibility = true
                subtitleAnimationGeneration &+= 1
                prepareSharedSubtitleAnimationStartState(
                    height: currentState.height,
                    alpha: currentState.alpha,
                    transform: currentState.transform,
                    shouldShowSubtitle: true
                )
                animateSubtitleTransform(
                    from: currentState.transform,
                    to: CATransform3DIdentity,
                    duration: SettingsDetailsAnimationCoordinator.toggleAnimationDuration,
                    timingFunction: Self.subtitleHeightAnimationTiming
                )
                subtitleHeightConstraint.animator().constant = expandedHeight
                subtitleLabel.animator().alphaValue = 1
                SettingsDetailsAnimationCoordinator.shared.registerLayoutRoot(layoutRoot, generation: toggleAnimationGeneration)
                SettingsDetailsAnimationCoordinator.shared.registerCompletion(generation: toggleAnimationGeneration) { [weak self, weak subtitleLabel, weak subtitleHeightConstraint] in
                    guard let self, let subtitleLabel, let subtitleHeightConstraint else { return }
                    subtitleHeightConstraint.constant = expandedHeight
                    subtitleLabel.alphaValue = 1
                    subtitleLabel.layer?.transform = CATransform3DIdentity
                    subtitleLabel.isHidden = false
                    self.subtitleContainerView?.isHidden = false
                    self.isAnimatingSubtitleVisibility = false
                }
                return
            }

            let animationDuration = subtitleAnimationDuration(from: currentState.height, to: expandedHeight, showing: true)
            let revealDelay = min(Self.subtitleRevealDelay, animationDuration * 0.25)
            let revealDuration = max(Self.subtitleShowAnimationMinDuration, animationDuration - revealDelay)

            guard shouldAnimate else {
                applySubtitleStateImmediately(height: expandedHeight, alpha: 1, isHidden: false, shouldShowSubtitle: true)
                return
            }

            isAnimatingSubtitleVisibility = true
            subtitleAnimationGeneration &+= 1
            let animationGeneration = subtitleAnimationGeneration
            subtitleLabel.alphaValue = currentState.alpha
            subtitleHeightConstraint.constant = currentState.height
            subtitleLabel.layer?.transform = currentState.transform
            layoutContainerIfNeeded()
            animateSubtitleHeight(
                to: expandedHeight,
                duration: animationDuration,
                timingFunction: Self.subtitleHeightAnimationTiming,
                generation: animationGeneration
            )
            animateSubtitleAlpha(
                to: 1,
                duration: revealDuration,
                timingFunction: SettingsDetailsAnimationCoordinator.subtitleFadeTiming,
                delay: revealDelay,
                generation: animationGeneration
            )
            animateSubtitleTransform(
                from: currentState.transform,
                to: CATransform3DIdentity,
                duration: revealDuration,
                timingFunction: Self.subtitleHeightAnimationTiming,
                delay: revealDelay,
                generation: animationGeneration
            )
            finalizeSubtitleAnimation(
                after: max(animationDuration, revealDelay + revealDuration),
                generation: animationGeneration
            ) { [weak self] in
                guard let self,
                      let subtitleLabel = self.subtitleLabel,
                      let subtitleHeightConstraint = self.subtitleHeightConstraint else { return }
                self.isAnimatingSubtitleVisibility = false
                subtitleHeightConstraint.constant = expandedHeight
                subtitleLabel.alphaValue = 1
                subtitleLabel.layer?.transform = CATransform3DIdentity
                subtitleLabel.isHidden = false
                self.subtitleContainerView?.isHidden = false
            }
            return
        }

        if usesSharedToggleAnimation {
            isAnimatingSubtitleVisibility = true
            subtitleAnimationGeneration &+= 1
            prepareSharedSubtitleAnimationStartState(
                height: currentState.height,
                alpha: currentState.alpha,
                transform: currentState.transform,
                shouldShowSubtitle: true
            )
            animateSubtitleTransform(
                from: currentState.transform,
                to: Self.hiddenSubtitleTransform,
                duration: SettingsDetailsAnimationCoordinator.toggleAnimationDuration,
                timingFunction: Self.subtitleHideAnimationTiming
            )
            subtitleLabel.animator().alphaValue = 0
            subtitleHeightConstraint.animator().constant = 0
            SettingsDetailsAnimationCoordinator.shared.registerLayoutRoot(layoutRoot, generation: toggleAnimationGeneration)
            SettingsDetailsAnimationCoordinator.shared.registerCompletion(generation: toggleAnimationGeneration) { [weak self, weak subtitleLabel, weak subtitleHeightConstraint] in
                guard let self, let subtitleLabel, let subtitleHeightConstraint else { return }
                subtitleHeightConstraint.constant = 0
                subtitleLabel.alphaValue = 0
                subtitleLabel.layer?.transform = Self.hiddenSubtitleTransform
                subtitleLabel.isHidden = true
                self.subtitleContainerView?.isHidden = true
                self.updateRowAlignment(shouldShowSubtitle: false)
                self.isAnimatingSubtitleVisibility = false
            }
            return
        }

        let animationDuration = subtitleAnimationDuration(from: currentState.height, to: 0, showing: false)
        let collapseLead = min(Self.subtitleCollapseLead, animationDuration * 0.34)
        let collapseDuration = max(Self.subtitleHideAnimationMinDuration, animationDuration - collapseLead)
        let fadeDuration = max(Self.subtitleHideAnimationMinDuration, animationDuration - (collapseLead * 0.35))

        guard shouldAnimate else {
            applySubtitleStateImmediately(height: 0, alpha: 0, isHidden: true, shouldShowSubtitle: false)
            return
        }

        isAnimatingSubtitleVisibility = true
        subtitleAnimationGeneration &+= 1
        let animationGeneration = subtitleAnimationGeneration
        subtitleContainerView.isHidden = false
        subtitleLabel.isHidden = false
        subtitleLabel.layer?.transform = currentState.transform
        animateSubtitleTransform(
            from: currentState.transform,
            to: Self.hiddenSubtitleTransform,
            duration: fadeDuration,
            timingFunction: Self.subtitleHideAnimationTiming,
            generation: animationGeneration
        )
        animateSubtitleAlpha(
            to: 0,
            duration: fadeDuration,
            timingFunction: Self.subtitleHideAnimationTiming,
            generation: animationGeneration
        )
        animateSubtitleHeight(
            to: 0,
            duration: collapseDuration,
            timingFunction: Self.subtitleHideAnimationTiming,
            delay: collapseLead,
            generation: animationGeneration
        )
        finalizeSubtitleAnimation(
            after: max(fadeDuration, collapseLead + collapseDuration),
            generation: animationGeneration
        ) { [weak self] in
            guard let self, let subtitleLabel = self.subtitleLabel else { return }
            subtitleLabel.isHidden = true
            subtitleLabel.alphaValue = 0
            subtitleLabel.layer?.transform = Self.hiddenSubtitleTransform
            self.subtitleContainerView?.isHidden = true
            self.updateRowAlignment(shouldShowSubtitle: false)
            self.isAnimatingSubtitleVisibility = false
        }
    }

    private func handleSharedTogglePhase(
        _ animationPhase: SettingsDetailsAnimationCoordinator.ToggleAnimationPhase,
        shouldShowSubtitle: Bool,
        currentState: (height: CGFloat, alpha: CGFloat, transform: CATransform3D),
        layoutRoot: NSView,
        toggleAnimationGeneration: UInt?,
        subtitleContainerView: NSView,
        subtitleLabel: NSTextField,
        subtitleHeightConstraint: NSLayoutConstraint
    ) {
        switch animationPhase {
        case .subtitleFade:
            guard !shouldShowSubtitle else { return }

            isAnimatingSubtitleVisibility = true
            subtitleAnimationGeneration &+= 1
            let animationGeneration = subtitleAnimationGeneration
            let expectedConstraintIdentifier = ObjectIdentifier(subtitleHeightConstraint)
            prepareSharedSubtitleAnimationStartState(
                height: currentState.height,
                alpha: currentState.alpha,
                transform: currentState.transform,
                shouldShowSubtitle: true
            )

            animateSubtitleTransform(
                from: currentState.transform,
                to: Self.hiddenSubtitleTransform,
                duration: SettingsDetailsAnimationCoordinator.subtitleFadeDuration(for: false),
                timingFunction: SettingsDetailsAnimationCoordinator.subtitleFadeTiming
            )

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = SettingsDetailsAnimationCoordinator.subtitleFadeDuration(for: false)
                context.timingFunction = SettingsDetailsAnimationCoordinator.subtitleFadeTiming
                context.allowsImplicitAnimation = true
                subtitleLabel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          animationGeneration == self.subtitleAnimationGeneration,
                          let subtitleLabel = self.subtitleLabel,
                          self.subtitleHeightConstraint.map(ObjectIdentifier.init) == expectedConstraintIdentifier else { return }
                    subtitleLabel.alphaValue = 0
                    subtitleLabel.layer?.transform = Self.hiddenSubtitleTransform
                    self.isAnimatingSubtitleVisibility = false
                }
            })

        case .layoutTransition:
            SettingsDetailsAnimationCoordinator.shared.registerLayoutRoot(layoutRoot, generation: toggleAnimationGeneration)

            if shouldShowSubtitle {
                isAnimatingSubtitleVisibility = true
                subtitleAnimationGeneration &+= 1
                let expandedHeight = measuredSubtitleHeight(for: subtitleLabel)
                subtitleExpandedHeight = expandedHeight

                prepareSharedSubtitleAnimationStartState(
                    height: currentState.height,
                    alpha: currentState.alpha,
                    transform: currentState.transform,
                    shouldShowSubtitle: true
                )

                animateSubtitleTransform(
                    from: Self.hiddenSubtitleTransform,
                    to: CATransform3DIdentity,
                    duration: SettingsDetailsAnimationCoordinator.subtitleFadeDuration(for: true),
                    timingFunction: SettingsDetailsAnimationCoordinator.sectionResizeTiming(for: true),
                    delay: SettingsDetailsAnimationCoordinator.subtitleFadeInDelay,
                    generation: subtitleAnimationGeneration
                )

                subtitleContainerView.isHidden = false
                subtitleLabel.isHidden = false
                subtitleLabel.alphaValue = currentState.alpha
                subtitleLabel.layer?.transform = currentState.transform
                subtitleHeightConstraint.animator().constant = expandedHeight
                animateSubtitleAlpha(
                    to: 1,
                    duration: SettingsDetailsAnimationCoordinator.subtitleFadeDuration(for: true),
                    timingFunction: SettingsDetailsAnimationCoordinator.subtitleFadeTiming,
                    delay: SettingsDetailsAnimationCoordinator.subtitleFadeInDelay,
                    generation: subtitleAnimationGeneration
                )

                SettingsDetailsAnimationCoordinator.shared.registerCompletion(generation: toggleAnimationGeneration) { [weak self, weak subtitleLabel, weak subtitleHeightConstraint] in
                    guard let self, let subtitleLabel, let subtitleHeightConstraint else { return }
                    subtitleHeightConstraint.constant = expandedHeight
                    subtitleLabel.alphaValue = 1
                    subtitleLabel.layer?.transform = CATransform3DIdentity
                    subtitleLabel.isHidden = false
                    self.subtitleContainerView?.isHidden = false
                    self.updateRowAlignment(shouldShowSubtitle: true)
                    self.isAnimatingSubtitleVisibility = false
                }
                return
            }

            isAnimatingSubtitleVisibility = true
            subtitleAnimationGeneration &+= 1
            prepareSharedSubtitleAnimationStartState(
                height: currentState.height,
                alpha: 0,
                transform: Self.hiddenSubtitleTransform,
                shouldShowSubtitle: true
            )

            subtitleHeightConstraint.animator().constant = 0

            SettingsDetailsAnimationCoordinator.shared.registerCompletion(generation: toggleAnimationGeneration) { [weak self, weak subtitleLabel, weak subtitleHeightConstraint] in
                guard let self, let subtitleLabel, let subtitleHeightConstraint else { return }
                subtitleHeightConstraint.constant = 0
                subtitleLabel.alphaValue = 0
                subtitleLabel.layer?.transform = Self.hiddenSubtitleTransform
                subtitleLabel.isHidden = true
                self.subtitleContainerView?.isHidden = true
                self.updateRowAlignment(shouldShowSubtitle: false)
                self.isAnimatingSubtitleVisibility = false
            }
        }
    }

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
        let titleSuperBoundsWidth = titleLabel?.superview?.bounds.width ?? 0
        if titleSuperBoundsWidth > widest { widest = titleSuperBoundsWidth }
        let titleSuperFrameWidth = titleLabel?.superview?.frame.width ?? 0
        if titleSuperFrameWidth > widest { widest = titleSuperFrameWidth }
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
            let shouldShowSubtitle = SettingsDetails.isOn

            self.performWithoutAnimation {
                subtitleLabel.preferredMaxLayoutWidth = resolvedWidth
                if shouldShowSubtitle {
                    subtitleHeightConstraint.constant = measuredHeight
                }
                self.layoutContainerIfNeeded()
            }

            await Task.yield()

            guard !Task.isCancelled,
                  self.window != nil,
                  let settledSubtitleLabel = self.subtitleLabel,
                  let settledSubtitleHeightConstraint = self.subtitleHeightConstraint else { return }

            self.layoutAnimationRoot().layoutSubtreeIfNeeded()
            let settledWidth = self.measuredSubtitleWidth(for: settledSubtitleLabel, allowFallback: false)
            guard settledWidth > 1,
                  abs(settledWidth - settledSubtitleLabel.preferredMaxLayoutWidth) > Self.subtitleHeightEpsilon else { return }

            self.invalidateCachedSubtitleMeasurement()
            settledSubtitleLabel.preferredMaxLayoutWidth = settledWidth
            let settledHeight = self.measuredSubtitleHeight(for: settledSubtitleLabel)
            self.subtitleExpandedHeight = settledHeight

            self.performWithoutAnimation {
                if SettingsDetails.isOn {
                    settledSubtitleHeightConstraint.constant = settledHeight
                }
                self.layoutContainerIfNeeded()
            }
        }
    }

    private func synchronizeAnimatedSubtitleStateIfNeeded() -> (height: CGFloat, alpha: CGFloat, transform: CATransform3D) {
        guard let subtitleContainerView, let subtitleLabel, let subtitleHeightConstraint else {
            return (0, 0, CATransform3DIdentity)
        }

        let currentHeight = currentRenderedSubtitleHeight(for: subtitleContainerView)
        let currentAlpha = currentRenderedSubtitleAlpha(for: subtitleLabel)
        let currentTransform = currentRenderedSubtitleTransform(for: subtitleLabel)

        guard isAnimatingSubtitleVisibility else {
            return (currentHeight, currentAlpha, currentTransform)
        }

        guard hasActiveSubtitleAnimations(subtitleContainerView: subtitleContainerView, subtitleLabel: subtitleLabel) else {
            isAnimatingSubtitleVisibility = false
            return (currentHeight, currentAlpha, currentTransform)
        }

        subtitleAnimationGeneration &+= 1
        removeSubtitleAnimations()
        performWithoutAnimation {
            subtitleHeightConstraint.constant = currentHeight
            subtitleLabel.alphaValue = currentAlpha
            subtitleLabel.layer?.transform = currentTransform
            let isHidden = currentHeight <= Self.subtitleHeightEpsilon && currentAlpha <= Self.subtitleAlphaEpsilon
            subtitleContainerView.isHidden = isHidden
            subtitleLabel.isHidden = isHidden
            updateRowAlignment(shouldShowSubtitle: !isHidden)
            layoutContainerIfNeeded()
        }
        isAnimatingSubtitleVisibility = false
        return (currentHeight, currentAlpha, currentTransform)
    }

    private func currentRenderedSubtitleHeight(for subtitleContainerView: NSView) -> CGFloat {
        if hasActiveLayerAnimations(on: subtitleContainerView),
           let presentationHeight = subtitleContainerView.layer?.presentation()?.bounds.height {
            return max(0, presentationHeight)
        }
        if subtitleContainerView.frame.height > Self.subtitleHeightEpsilon {
            return subtitleContainerView.frame.height
        }
        return max(0, subtitleHeightConstraint?.constant ?? 0)
    }

    private func currentRenderedSubtitleAlpha(for subtitleLabel: NSTextField) -> CGFloat {
        if hasActiveLayerAnimations(on: subtitleLabel),
           let presentationAlpha = subtitleLabel.layer?.presentation()?.opacity {
            return min(max(CGFloat(presentationAlpha), 0), 1)
        }
        return min(max(CGFloat(subtitleLabel.alphaValue), 0), 1)
    }

    private func currentRenderedSubtitleTransform(for subtitleLabel: NSTextField) -> CATransform3D {
        if hasActiveLayerAnimations(on: subtitleLabel),
           let presentationTransform = subtitleLabel.layer?.presentation()?.transform {
            return presentationTransform
        }
        return subtitleLabel.layer?.transform ?? CATransform3DIdentity
    }

    private func isSubtitleStateSettled(
        shouldShowSubtitle: Bool,
        currentState: (height: CGFloat, alpha: CGFloat, transform: CATransform3D),
        targetExpandedHeight: CGFloat,
        subtitleContainerView: NSView,
        subtitleLabel: NSTextField
    ) -> Bool {
        if shouldShowSubtitle {
            return !subtitleContainerView.isHidden
                && !subtitleLabel.isHidden
                && abs(currentState.height - targetExpandedHeight) <= Self.subtitleHeightEpsilon
                && currentState.alpha >= (1 - Self.subtitleAlphaEpsilon)
                && isSubtitleTransformSettled(currentState.transform, shouldShowSubtitle: true)
        }

        return (subtitleContainerView.isHidden && subtitleLabel.isHidden)
            || (
                currentState.height <= Self.subtitleHeightEpsilon
                    && currentState.alpha <= Self.subtitleAlphaEpsilon
                    && isSubtitleTransformSettled(currentState.transform, shouldShowSubtitle: false)
            )
    }

    private func isSubtitleTransformSettled(_ transform: CATransform3D, shouldShowSubtitle: Bool) -> Bool {
        let targetTransform = shouldShowSubtitle ? CATransform3DIdentity : Self.hiddenSubtitleTransform
        let epsilon = CGFloat(0.001)
        return abs(transform.m11 - targetTransform.m11) <= epsilon
            && abs(transform.m22 - targetTransform.m22) <= epsilon
            && abs(transform.m41 - targetTransform.m41) <= epsilon
            && abs(transform.m42 - targetTransform.m42) <= epsilon
    }

    private func subtitleAnimationDuration(from currentHeight: CGFloat, to targetHeight: CGFloat, showing: Bool) -> TimeInterval {
        let totalTravel = max(max(subtitleExpandedHeight, targetHeight), Self.subtitleHeightEpsilon)
        let remainingTravel = abs(targetHeight - currentHeight)
        let normalizedTravel = min(max(remainingTravel / totalTravel, 0), 1)
        let minDuration = showing ? Self.subtitleShowAnimationMinDuration : Self.subtitleHideAnimationMinDuration
        let maxDuration = showing ? Self.subtitleShowAnimationMaxDuration : Self.subtitleHideAnimationMaxDuration
        let durationRange = maxDuration - minDuration
        return minDuration + (durationRange * normalizedTravel)
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

    private static var hiddenSubtitleTransform: CATransform3D {
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, 0, Self.subtitleHiddenYOffset, 0)
        transform = CATransform3DScale(transform, Self.subtitleHiddenScale, Self.subtitleHiddenScale, 1)
        return transform
    }

    private func prepareSharedSubtitleAnimationStartState(
        height: CGFloat,
        alpha: CGFloat,
        transform: CATransform3D,
        shouldShowSubtitle: Bool
    ) {
        guard let subtitleContainerView, let subtitleLabel, let subtitleHeightConstraint else { return }

        performWithoutAnimation {
            subtitleContainerView.isHidden = false
            subtitleLabel.isHidden = false
            subtitleHeightConstraint.constant = height
            subtitleLabel.alphaValue = alpha
            subtitleLabel.layer?.transform = transform
            updateRowAlignment(shouldShowSubtitle: shouldShowSubtitle)
            self.layoutSubtreeIfNeeded()
        }
    }

    private func applySubtitleStateImmediately(height: CGFloat, alpha: CGFloat, isHidden: Bool, shouldShowSubtitle: Bool) {
        guard let subtitleContainerView, let subtitleLabel, let subtitleHeightConstraint else { return }

        _ = synchronizeAnimatedSubtitleStateIfNeeded()
        performWithoutAnimation {
            subtitleHeightConstraint.constant = height
            subtitleLabel.alphaValue = alpha
            subtitleLabel.layer?.transform = shouldShowSubtitle ? CATransform3DIdentity : Self.hiddenSubtitleTransform
            subtitleContainerView.isHidden = isHidden
            subtitleLabel.isHidden = isHidden
            updateRowAlignment(shouldShowSubtitle: shouldShowSubtitle)
            layoutContainerIfNeeded()
        }
        isAnimatingSubtitleVisibility = false
    }

    private func applySubtitleStateForInactiveTab(
        shouldShowSubtitle: Bool,
        subtitleContainerView: NSView,
        subtitleLabel: NSTextField,
        subtitleHeightConstraint: NSLayoutConstraint
    ) {
        let targetHeight: CGFloat
        if shouldShowSubtitle {
            let expandedHeight = measuredSubtitleHeight(for: subtitleLabel)
            subtitleExpandedHeight = expandedHeight
            targetHeight = expandedHeight
        } else {
            targetHeight = 0
        }

        isAnimatingSubtitleVisibility = false
        performWithoutAnimation {
            subtitleHeightConstraint.constant = targetHeight
            subtitleLabel.alphaValue = shouldShowSubtitle ? 1 : 0
            subtitleLabel.layer?.transform = shouldShowSubtitle ? CATransform3DIdentity : Self.hiddenSubtitleTransform
            subtitleContainerView.isHidden = !shouldShowSubtitle
            subtitleLabel.isHidden = !shouldShowSubtitle
            updateRowAlignment(shouldShowSubtitle: shouldShowSubtitle)
        }
    }

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

    private func hasActiveLayerAnimations(on view: NSView) -> Bool {
        !(view.layer?.animationKeys()?.isEmpty ?? true)
    }

    private func hasActiveSubtitleAnimations(subtitleContainerView: NSView, subtitleLabel: NSTextField) -> Bool {
        hasActiveLayerAnimations(on: subtitleContainerView) || hasActiveLayerAnimations(on: subtitleLabel)
    }

    private func updateRowAlignment(shouldShowSubtitle: Bool) {
        _ = shouldShowSubtitle
        rowStack?.alignment = .top
    }

    private func animateSubtitleTransform(
        from: CATransform3D,
        to: CATransform3D,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        delay: TimeInterval = 0,
        generation: UInt? = nil
    ) {
        performSubtitleAnimation(after: delay, generation: generation) { [weak self] in
            guard let self, let layer = self.subtitleLabel?.layer else { return }

            layer.removeAnimation(forKey: Self.subtitleTransformAnimationKey)

            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: from)
            animation.toValue = NSValue(caTransform3D: to)
            animation.duration = duration
            animation.timingFunction = timingFunction
            animation.isRemovedOnCompletion = true

            layer.add(animation, forKey: Self.subtitleTransformAnimationKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = to
            CATransaction.commit()
        }
    }

    private func animateSubtitleAlpha(
        to targetAlpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        delay: TimeInterval = 0,
        generation: UInt
    ) {
        performSubtitleAnimation(after: delay, generation: generation) { [weak self] in
            guard let self, let subtitleLabel = self.subtitleLabel else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timingFunction
                context.allowsImplicitAnimation = true
                subtitleLabel.animator().alphaValue = targetAlpha
            }
        }
    }

    private func animateSubtitleHeight(
        to targetHeight: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        delay: TimeInterval = 0,
        generation: UInt
    ) {
        performSubtitleAnimation(after: delay, generation: generation) { [weak self] in
            guard let self, let subtitleHeightConstraint = self.subtitleHeightConstraint else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timingFunction
                context.allowsImplicitAnimation = true
                subtitleHeightConstraint.animator().constant = targetHeight
                self.layoutContainerIfNeeded()
            }
        }
    }

    private func finalizeSubtitleAnimation(after delay: TimeInterval, generation: UInt, updates: @escaping () -> Void) {
        performSubtitleAnimation(after: delay, generation: generation, updates)
    }

    private func performSubtitleAnimation(after delay: TimeInterval, generation: UInt? = nil, _ updates: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self else { return }
            if let generation, generation != self.subtitleAnimationGeneration {
                return
            }

            updates()
        }
    }

    private func removeSubtitleAnimations() {
        subtitleContainerView?.layer?.removeAllAnimations()
        subtitleLabel?.layer?.removeAllAnimations()
    }
}
