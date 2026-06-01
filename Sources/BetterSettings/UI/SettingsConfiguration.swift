//
//  SettingsConfiguration.swift
//  BetterSettings
//
//  Everything an app supplies to build its settings window: the ordered tabs,
//  the searchable catalog, and a factory that produces the content controller
//  for each tab. The window/sidebar/search machinery is provided by the package.
//

import AppKit

/// Controls whether visited-but-inactive tab controllers stay in memory or are
/// unloaded — and lazily rebuilt from `contentProvider` on revisit — to lower RAM.
///
/// Unloading never affects animation motion or search: show-details state lives in
/// `UserDefaults`, the search catalog is pure value data, and scroll already resets
/// to top on every visit. The only cost is a rebuild (`setupContent()` + one
/// subtitle-height re-measure) when you return to an evicted tab.
public struct SettingsTabUnloadPolicy: Sendable, Equatable {
    /// How many recently-used *inactive* tabs to keep live besides the active one.
    /// `.max` means "never evict" (keep every visited tab while the window is open).
    public let keepRecentInactive: Int
    /// When the settings window resigns key (user moved focus away), drop down to
    /// the active tab only, freeing the recently-kept inactive tabs.
    public let dropsToActiveWhenWindowResignsKey: Bool

    public init(keepRecentInactive: Int, dropsToActiveWhenWindowResignsKey: Bool) {
        self.keepRecentInactive = max(0, keepRecentInactive)
        self.dropsToActiveWhenWindowResignsKey = dropsToActiveWhenWindowResignsKey
    }

    /// Never unload visited tabs while the window is open (default; matches the
    /// original smoothness-first behavior and adds no bookkeeping).
    public static let keepAll = SettingsTabUnloadPolicy(
        keepRecentInactive: .max,
        dropsToActiveWhenWindowResignsKey: false
    )

    /// Recommended low-RAM policy: keep the active tab plus the one most-recently
    /// used tab live while the window is focused, and drop to active-only when it
    /// loses focus. Toggling between two tabs never rebuilds.
    public static let balanced = SettingsTabUnloadPolicy(
        keepRecentInactive: 1,
        dropsToActiveWhenWindowResignsKey: true
    )

    /// Keep the active tab plus `n` recently-used inactive tabs.
    public static func lruKeep(_ n: Int, dropsToActiveWhenWindowResignsKey: Bool = true) -> SettingsTabUnloadPolicy {
        SettingsTabUnloadPolicy(keepRecentInactive: n, dropsToActiveWhenWindowResignsKey: dropsToActiveWhenWindowResignsKey)
    }
}

@MainActor
public struct SettingsConfiguration {
    /// Ordered sidebar tabs (top to bottom).
    public var tabs: [SettingsTab]
    /// Searchable settings across all tabs, in interface order.
    public var searchItems: [SettingsSearchItem]
    /// Produces the content controller for a tab. Called lazily on first show and
    /// cached. With a non-`.keepAll` `tabUnloadPolicy` it may be called again to
    /// rebuild a tab that was unloaded to reclaim memory, so keep it pure (no
    /// one-shot side effects that assume a single invocation).
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
    /// Whether and how to unload inactive tab controllers to lower RAM. Defaults
    /// to `.keepAll` (original behavior). See `SettingsTabUnloadPolicy`.
    public var tabUnloadPolicy: SettingsTabUnloadPolicy

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
        sidebarWidth: CGFloat = 213,
        tabUnloadPolicy: SettingsTabUnloadPolicy = .keepAll
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
        self.tabUnloadPolicy = tabUnloadPolicy
    }

    func tab(for id: String) -> SettingsTab? {
        tabs.first { $0.id == id }
    }
}
