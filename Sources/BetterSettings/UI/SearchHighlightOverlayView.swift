//
//  SearchHighlightOverlayView.swift
//  BetterSettings
//
//  Accent-tinted overlay that briefly flashes over the target of a
//  search-result navigation. Transparent to hit-testing so it never blocks the
//  control it highlights.
//

import AppKit

@MainActor
final class SearchHighlightOverlayView: NSView {
    private let cornerRadius: CGFloat
    private let fillOpacity: CGFloat
    private let strokeOpacity: CGFloat
    private let strokeWidth: CGFloat

    init(cornerRadius: CGFloat, fillOpacity: CGFloat, strokeOpacity: CGFloat, strokeWidth: CGFloat) {
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerCurve = .continuous
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = strokeWidth
        layer?.backgroundColor = accent.withAlphaComponent(fillOpacity).cgColor
        layer?.borderColor = accent.withAlphaComponent(strokeOpacity).cgColor
    }
}
