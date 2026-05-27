//
//  SettingsTab.swift
//  BetterSettings
//
//  A single top-level row in the settings sidebar. Carries everything the
//  sidebar needs to render itself (localized title + macOS-style gradient
//  icon badge) decoupled from any content implementation.
//

import CoreGraphics

/// Visual styling for a tab's rounded gradient icon badge, mirroring the
/// macOS System Settings look (white SF Symbol over a vertical gradient).
public struct SettingsTabIconStyle: Sendable, Hashable {
    public enum SymbolColorMode: Sendable, Hashable {
        /// SF Symbol hierarchical rendering (depth via opacity).
        case hierarchical
        /// Flat single-color palette rendering.
        case monochrome
    }

    public var symbolColor: SettingsColor
    public var gradientStart: SettingsColor
    public var gradientEnd: SettingsColor
    /// Multiplier applied to the base 16pt symbol size (clamped 0.7...2.0).
    public var symbolScale: CGFloat
    public var symbolColorMode: SymbolColorMode

    public init(
        symbolColor: SettingsColor = .white,
        gradientStart: SettingsColor,
        gradientEnd: SettingsColor,
        symbolScale: CGFloat = 1.0,
        symbolColorMode: SymbolColorMode = .hierarchical
    ) {
        self.symbolColor = symbolColor
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.symbolScale = symbolScale
        self.symbolColorMode = symbolColorMode
    }

    /// Solid-tint convenience: same color top and bottom.
    public static func solid(
        _ color: SettingsColor,
        symbolColor: SettingsColor = .white,
        symbolScale: CGFloat = 1.0,
        symbolColorMode: SymbolColorMode = .hierarchical
    ) -> SettingsTabIconStyle {
        SettingsTabIconStyle(
            symbolColor: symbolColor,
            gradientStart: color,
            gradientEnd: color,
            symbolScale: symbolScale,
            symbolColorMode: symbolColorMode
        )
    }

    /// Neutral grey badge used by the demo / as a sensible default.
    public static let neutral = SettingsTabIconStyle(
        gradientStart: SettingsColor(hex: 0x898A8F),
        gradientEnd: SettingsColor(hex: 0x67686E)
    )
}

public struct SettingsTab: Identifiable, Sendable, Hashable {
    /// Stable identifier used by the router and search items.
    public let id: String
    /// Localized title shown in the sidebar and the window title bar.
    public let title: String
    /// SF Symbol name rendered inside the gradient badge.
    public let icon: String
    public let iconStyle: SettingsTabIconStyle
    /// When `true` the sidebar renders a small "BETA" pill after the title.
    public let isBeta: Bool

    public init(
        id: String,
        title: String,
        icon: String,
        iconStyle: SettingsTabIconStyle = .neutral,
        isBeta: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.iconStyle = iconStyle
        self.isBeta = isBeta
    }
}
