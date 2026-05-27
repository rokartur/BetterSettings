//
//  SettingsColor.swift
//  BetterSettings
//
//  Sendable RGBA color so the dependency-free domain layer can describe tab
//  icon gradients without importing AppKit. Converted to `NSColor` in the UI
//  layer (see `SettingsColor+NSColor`).
//

import CoreGraphics

public struct SettingsColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// White-point convenience (e.g. `SettingsColor(white: 1)` for pure white).
    public init(white: Double, alpha: Double = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    /// 8-bit-per-channel convenience matching design hand-offs (`0...255`).
    public init(r: Double, g: Double, b: Double, alpha: Double = 1) {
        self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
    }

    /// Hex convenience, `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            r: Double((hex >> 16) & 0xFF),
            g: Double((hex >> 8) & 0xFF),
            b: Double(hex & 0xFF),
            alpha: alpha
        )
    }

    public static let white = SettingsColor(white: 1)
    public static let black = SettingsColor(white: 0)
}
