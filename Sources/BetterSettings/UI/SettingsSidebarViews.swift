//
//  SettingsSidebarViews.swift
//  BetterSettings
//
//  Private subviews backing the sidebar table: the cell (tab badge or search
//  result), the gradient icon badge, the locked-tint symbol image view, the
//  "BETA" pill, and the row view that paints the rounded selection capsule.
//

import AppKit
import QuartzCore

// MARK: - Cell

final class SidebarCellView: NSTableCellView {

    private let iconContainerSize: CGFloat
    private let contentPadding: CGFloat

    private let iconBadge: SidebarIconBadgeView
    private let symbolView: SidebarSymbolImageView
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let betaBadge = SidebarBetaBadgeView()

    private var baseTitleColor: NSColor = .labelColor
    private var baseSubtitleColor: NSColor = .secondaryLabelColor
    private var gradientStart: NSColor?
    private var gradientEnd: NSColor?
    private var allowsSelectionStyling = true
    // Skips redundant re-applies (each one rebuilds CGColor arrays + dirties the
    // gradient layer). Invalidated whenever the cell is reconfigured.
    private var lastSelectionStyle: (isSelected: Bool, isEmphasized: Bool)?

    // Toggled constraints between tab and search-result layouts.
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    private var titleLeadingWithIcon: NSLayoutConstraint!
    private var titleLeadingWithoutIcon: NSLayoutConstraint!
    private var titleCenterY: NSLayoutConstraint!
    private var titleTop: NSLayoutConstraint!
    private var subtitleTop: NSLayoutConstraint!
    private var subtitleBottom: NSLayoutConstraint!
    private var titleTrailingWithBadge: NSLayoutConstraint!
    private var titleTrailingWithoutBadge: NSLayoutConstraint!

    init(
        iconContainerSize: CGFloat,
        iconCornerRadius: CGFloat,
        contentPadding: CGFloat,
        titleFontSize: CGFloat,
        subtitleFontSize: CGFloat
    ) {
        self.iconContainerSize = iconContainerSize
        self.contentPadding = contentPadding
        self.iconBadge = SidebarIconBadgeView(cornerRadius: iconCornerRadius)
        self.symbolView = SidebarSymbolImageView()
        super.init(frame: .zero)
        setup(titleFontSize: titleFontSize, subtitleFontSize: subtitleFontSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup(titleFontSize: CGFloat, subtitleFontSize: CGFloat) {
        // Source-list cells are inset ~16pt on each side; pull a content guide
        // back so icon/text align inside the 9pt rounded selection capsule.
        let leadingCompensation: CGFloat = 9 - 16
        let trailingCompensation: CGFloat = 16 - 6

        let contentGuide = NSLayoutGuide()
        addLayoutGuide(contentGuide)

        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconBadge)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.imageAlignment = .alignCenter
        symbolView.imageScaling = .scaleProportionallyDown
        iconBadge.addSubview(symbolView)
        self.imageView = symbolView

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: titleFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleField)
        self.textField = titleField

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = .systemFont(ofSize: subtitleFontSize)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(subtitleField)

        betaBadge.translatesAutoresizingMaskIntoConstraints = false
        betaBadge.isHidden = true
        addSubview(betaBadge)

        let preferredWidth = contentGuide.widthAnchor.constraint(equalToConstant: 195)
        preferredWidth.priority = .defaultHigh

        iconWidth = symbolView.widthAnchor.constraint(equalToConstant: 16)
        iconHeight = symbolView.heightAnchor.constraint(equalToConstant: 16)

        titleLeadingWithIcon = titleField.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: contentPadding)
        titleLeadingWithoutIcon = titleField.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: contentPadding)
        titleCenterY = titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        titleTop = titleField.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        subtitleTop = subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1)
        subtitleBottom = subtitleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        titleTrailingWithBadge = titleField.trailingAnchor.constraint(lessThanOrEqualTo: betaBadge.leadingAnchor, constant: -4)
        titleTrailingWithoutBadge = titleField.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -contentPadding)

        NSLayoutConstraint.activate([
            contentGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingCompensation),
            preferredWidth,
            contentGuide.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: trailingCompensation),

            iconBadge.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: contentPadding),
            iconBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: iconContainerSize),
            iconBadge.heightAnchor.constraint(equalToConstant: iconContainerSize),

            symbolView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            iconWidth, iconHeight,

            betaBadge.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -contentPadding),
            betaBadge.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -contentPadding),
        ])
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { symbolView.reapplyTint() }
    }

    // MARK: - Configuration

    func configureAsTab(
        title: String,
        iconImage: NSImage?,
        iconScale: CGFloat,
        gradientStart: NSColor,
        gradientEnd: NSColor,
        isBeta: Bool
    ) {
        lastSelectionStyle = nil
        setIconVisible(true)
        iconWidth.constant = iconScale
        iconHeight.constant = iconScale
        symbolView.image = iconImage
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        baseTitleColor = .labelColor
        baseSubtitleColor = .secondaryLabelColor
        allowsSelectionStyling = true

        titleField.stringValue = title
        setSubtitle(nil)
        setBetaVisible(isBeta)
        iconBadge.setGradient(start: gradientStart, end: gradientEnd, opacity: 1)
    }

    func configureAsSearchResult(title: String, subtitle: String) {
        lastSelectionStyle = nil
        setIconVisible(false)
        symbolView.image = nil
        gradientStart = nil
        gradientEnd = nil
        baseTitleColor = .labelColor
        baseSubtitleColor = .secondaryLabelColor
        allowsSelectionStyling = true
        titleField.stringValue = title
        setSubtitle(subtitle)
        setBetaVisible(false)
        iconBadge.setGradient(start: nil, end: nil)
    }

    func configureAsEmpty(text: String) {
        lastSelectionStyle = nil
        setIconVisible(false)
        symbolView.image = nil
        gradientStart = nil
        gradientEnd = nil
        baseTitleColor = .tertiaryLabelColor
        baseSubtitleColor = .tertiaryLabelColor
        allowsSelectionStyling = false
        titleField.stringValue = text
        setSubtitle(nil)
        setBetaVisible(false)
        iconBadge.setGradient(start: nil, end: nil)
    }

    private func setIconVisible(_ visible: Bool) {
        iconBadge.isHidden = !visible
        symbolView.isHidden = !visible
        titleLeadingWithIcon.isActive = visible
        titleLeadingWithoutIcon.isActive = !visible
    }

    private func setSubtitle(_ text: String?) {
        let normalized = text?
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ") ?? ""
        let hasSubtitle = !normalized.isEmpty
        subtitleField.stringValue = normalized
        subtitleField.isHidden = !hasSubtitle
        titleCenterY.isActive = !hasSubtitle
        titleTop.isActive = hasSubtitle
        subtitleTop.isActive = hasSubtitle
        subtitleBottom.isActive = hasSubtitle
    }

    private func setBetaVisible(_ visible: Bool) {
        betaBadge.isHidden = !visible
        titleTrailingWithBadge.isActive = visible
        titleTrailingWithoutBadge.isActive = !visible
    }

    // MARK: - Selection styling

    func applySelectionStyle(isSelected: Bool, isEmphasized: Bool) {
        if let lastSelectionStyle, lastSelectionStyle == (isSelected, isEmphasized) { return }
        lastSelectionStyle = (isSelected, isEmphasized)
        let dim = !isEmphasized

        guard allowsSelectionStyling, isSelected else {
            titleField.textColor = dim ? baseTitleColor.applyingInactiveSelectedFactor() : baseTitleColor
            subtitleField.textColor = dim ? baseSubtitleColor.applyingInactiveSelectedFactor() : baseSubtitleColor
            iconBadge.setGradient(start: gradientStart, end: gradientEnd, opacity: dim ? 0.7 : 1)
            betaBadge.applySelectionState(active: false)
            return
        }

        if isEmphasized {
            let selected = NSColor.alternateSelectedControlTextColor
            titleField.textColor = selected
            subtitleField.textColor = selected.withAlphaComponent(0.84)
        } else {
            titleField.textColor = baseTitleColor.applyingInactiveSelectedFactor()
            subtitleField.textColor = baseSubtitleColor.applyingInactiveSelectedFactor()
        }
        iconBadge.setGradient(start: gradientStart, end: gradientEnd, opacity: isEmphasized ? 1 : 0.7)
        betaBadge.applySelectionState(active: isEmphasized)
    }
}

// MARK: - Gradient icon badge

final class SidebarIconBadgeView: NSView {
    override var allowsVibrancy: Bool { false }

    private let gradientLayer = CAGradientLayer()
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        layer?.shadowOpacity = 0.35
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = cornerRadius
        gradientLayer.cornerCurve = .continuous
        gradientLayer.masksToBounds = true
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    func setGradient(start: NSColor?, end: NSColor?, opacity: CGFloat = 1) {
        guard let start, let end else {
            gradientLayer.colors = nil
            gradientLayer.isHidden = true
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
            return
        }
        let clamped = max(0, min(opacity, 1))
        gradientLayer.isHidden = false
        gradientLayer.colors = [start.applyingOpacityFactor(clamped).cgColor, end.applyingOpacityFactor(clamped).cgColor]
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.white.withAlphaComponent(0.24 * clamped).cgColor
        layer?.shadowOpacity = Float(0.35 * clamped)
    }
}

// MARK: - Symbol image view (locked template tint)

final class SidebarSymbolImageView: NSImageView {
    override var allowsVibrancy: Bool { false }

    override var image: NSImage? {
        didSet {
            // Tab icons are full-color (non-template); leave them as drawn.
            image?.isTemplate = false
        }
    }

    func reapplyTint() {
        // Color tab icons keep their own palette; nothing to recolor.
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowOpacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - BETA pill

final class SidebarBetaBadgeView: NSView {
    private let label = NSTextField(labelWithString: "BETA")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.alignment = .center
        label.isBezeled = false
        label.isBordered = false
        label.drawsBackground = false
        label.isSelectable = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1.5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
        ])
        applySelectionState(active: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applySelectionState(active: Bool) {
        if active {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
            label.textColor = .alternateSelectedControlTextColor
        } else {
            layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.18).cgColor
            layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.45).cgColor
            label.textColor = .systemPink
        }
    }
}

// MARK: - Row view (rounded selection capsule)

final class SidebarRowView: NSTableRowView {
    private let maxContentWidth: CGFloat
    private let leadingInset: CGFloat
    private let trailingInset: CGFloat
    private let cornerRadius: CGFloat = 8

    var selectionEmphasized: Bool = true {
        didSet { if oldValue != selectionEmphasized { needsDisplay = true } }
    }

    init(maxContentWidth: CGFloat, leadingInset: CGFloat, trailingInset: CGFloat) {
        self.maxContentWidth = maxContentWidth
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        super.init(frame: .zero)
        selectionHighlightStyle = .regular
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let availableWidth = max(0, bounds.width - leadingInset - trailingInset)
        let selectionWidth = min(maxContentWidth, availableWidth)
        guard selectionWidth > 0, bounds.height > 0 else { return }

        let rect = NSRect(x: leadingInset, y: 0, width: selectionWidth, height: bounds.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        let color: NSColor = selectionEmphasized ? .controlAccentColor : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        path.fill()
    }
}
