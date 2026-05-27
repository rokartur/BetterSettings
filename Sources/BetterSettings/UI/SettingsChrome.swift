//
//  SettingsChrome.swift
//  BetterSettings
//
//  Shared AppKit styling primitives: SettingsColor → NSColor bridging and the
//  semantic card/border/divider colors used by section containers.
//

import AppKit

extension SettingsColor {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

/// Centralized section-card chrome so every container matches macOS System
/// Settings: 14pt continuous corners, hairline border, faint fill.
enum SettingsSectionChrome {
    static let cornerRadius: CGFloat = 14
    static let borderWidth: CGFloat = 0.5

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func fillColor(for appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.025)
    }

    static func borderColor(for appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.05)
    }

    static func dividerColor(for appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.06)
    }
}

extension NSColor {
    /// Brightness factor applied to selected text/icons in an inactive window
    /// (FFFFFF → ~A3A3A3) so selection still reads as "selected" but dimmed.
    private static let inactiveSelectedBrightnessFactor: CGFloat = 163.0 / 255.0

    func applyingInactiveSelectedFactor() -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        let factor = NSColor.inactiveSelectedBrightnessFactor
        return NSColor(
            srgbRed: rgb.redComponent * factor,
            green: rgb.greenComponent * factor,
            blue: rgb.blueComponent * factor,
            alpha: rgb.alphaComponent
        )
    }

    func applyingOpacityFactor(_ factor: CGFloat) -> NSColor {
        withAlphaComponent(alphaComponent * max(0, min(factor, 1)))
    }
}
