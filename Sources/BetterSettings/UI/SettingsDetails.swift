//
//  SettingsDetails.swift
//  BetterSettings
//
//  Backing store for the sidebar "Show Details" toggle. Rows observe
//  `showDetailsDidChange` and reveal/hide their subtitles in step. The defaults
//  store and key are configurable via `SettingsConfiguration`.
//

import Foundation

extension Notification.Name {
    static let betterSettingsShowDetailsDidChange = Notification.Name("BetterSettings.showDetailsDidChange")
}

@MainActor
enum SettingsDetails {
    static var defaults: UserDefaults = .standard
    static var defaultsKey = "BetterSettings.showDetails"

    /// Whether row subtitles are shown. Defaults to `true` when unset.
    static var isOn: Bool {
        (defaults.object(forKey: defaultsKey) as? Bool) ?? true
    }

    static func write(_ on: Bool) {
        defaults.set(on, forKey: defaultsKey)
    }
}
