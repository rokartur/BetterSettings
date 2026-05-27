//
//  SettingsSectionView.swift
//  BetterSettings
//
//  Rounded-card section container: optional bold header above a hairline-bordered
//  card holding a vertical stack of rows/dividers. Matches macOS System Settings.
//

import AppKit

@MainActor
public final class SettingsSectionView: NSView {

    private static let cornerRadius = SettingsSectionChrome.cornerRadius
    private static let contentPadding: CGFloat = 12
    private static let contentSpacing: CGFloat = 10
    private static let headerBottomSpacing: CGFloat = 10

    private let outerStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let cardView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Vertical stack inside the card. Rows and dividers are added here.
    public let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsSectionView.contentSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// - Parameter title: Optional bold header drawn above the card.
    public init(title: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupViews(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCardAppearance()
    }

    private func setupViews(title: String?) {
        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let title {
            let header = makeHeader(title: title)
            outerStack.addArrangedSubview(header)
            outerStack.setCustomSpacing(Self.headerBottomSpacing, after: header)
            NSLayoutConstraint.activate([
                header.leadingAnchor.constraint(equalTo: outerStack.leadingAnchor, constant: 4),
                header.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor, constant: -4),
            ])
        }

        outerStack.addArrangedSubview(cardView)
        cardView.wantsLayer = true
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: outerStack.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor),
        ])
        updateCardAppearance()

        cardView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Self.contentPadding),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Self.contentPadding),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Self.contentPadding),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Self.contentPadding),
        ])
        contentStack.setHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func updateCardAppearance() {
        guard let layer = cardView.layer else { return }
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.cornerRadius
        layer.backgroundColor = SettingsSectionChrome.fillColor(for: effectiveAppearance).cgColor
        layer.borderWidth = SettingsSectionChrome.borderWidth
        layer.borderColor = SettingsSectionChrome.borderColor(for: effectiveAppearance).cgColor
    }

    // MARK: - Public API

    /// Adds a full-width view to the card's content stack.
    public func addContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// Adds a hairline separator between rows.
    public func addDivider() {
        let divider = NSBox()
        divider.boxType = .separator
        addContent(divider)
    }

    private func makeHeader(title: String) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrapper.topAnchor),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }
}
