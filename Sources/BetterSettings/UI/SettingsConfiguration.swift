//
//  SettingsConfiguration.swift
//  BetterSettings
//
//  Everything an app supplies to build its settings window: the ordered tabs,
//  the searchable catalog, and a factory that produces the content controller
//  for each tab. The window/sidebar/search machinery is provided by the package.
//

import AppKit

@MainActor
public struct SettingsConfiguration {
    /// Ordered sidebar tabs (top to bottom).
    public var tabs: [SettingsTab]
    /// Searchable settings across all tabs, in interface order.
    public var searchItems: [SettingsSearchItem]
    /// Produces the content controller for a tab. Called lazily, once per tab,
    /// and the result is cached while the window is open.
    public var contentProvider: (_ tab: SettingsTab, _ router: SettingsRouter) -> SettingsTabViewController

    /// Window title for a tab. Defaults to the tab title.
    public var windowTitle: (SettingsTab) -> String
    /// Localized placeholder for the sidebar search field.
    public var searchPlaceholder: String
    /// Localized text for the sidebar "No matching settings" empty state.
    public var noResultsText: String
    /// Shows the sidebar-footer "Show Details" toggle that reveals row subtitles.
    public var showsDetailsToggle: Bool
    /// Localized "Show Details" label.
    public var showDetailsLabel: String
    /// UserDefaults store + key backing the "Show Details" state.
    public var defaults: UserDefaults
    public var showDetailsDefaultsKey: String
    /// Fixed content size of the window (matches macOS System Settings sizing).
    public var windowSize: CGSize
    /// Sidebar width in points.
    public var sidebarWidth: CGFloat

    public init(
        tabs: [SettingsTab],
        searchItems: [SettingsSearchItem] = [],
        contentProvider: @escaping (_ tab: SettingsTab, _ router: SettingsRouter) -> SettingsTabViewController,
        windowTitle: @escaping (SettingsTab) -> String = { $0.title },
        searchPlaceholder: String = "Search",
        noResultsText: String = "No matching settings",
        showsDetailsToggle: Bool = true,
        showDetailsLabel: String = "Show Details",
        defaults: UserDefaults = .standard,
        showDetailsDefaultsKey: String = "BetterSettings.showDetails",
        windowSize: CGSize = CGSize(width: 870, height: 650),
        sidebarWidth: CGFloat = 213
    ) {
        self.tabs = tabs
        self.searchItems = searchItems
        self.contentProvider = contentProvider
        self.windowTitle = windowTitle
        self.searchPlaceholder = searchPlaceholder
        self.noResultsText = noResultsText
        self.showsDetailsToggle = showsDetailsToggle
        self.showDetailsLabel = showDetailsLabel
        self.defaults = defaults
        self.showDetailsDefaultsKey = showDetailsDefaultsKey
        self.windowSize = windowSize
        self.sidebarWidth = sidebarWidth
    }

    func tab(for id: String) -> SettingsTab? {
        tabs.first { $0.id == id }
    }
}
