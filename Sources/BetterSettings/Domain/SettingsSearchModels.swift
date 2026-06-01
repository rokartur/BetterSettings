//
//  SettingsSearchModels.swift
//  BetterSettings
//
//  Search domain for the settings sidebar. An app declares one
//  `SettingsSearchItem` per searchable control; the sidebar searches them and
//  navigates to the owning tab + section anchor on selection.
//

import Foundation

/// A single searchable setting. Strings are expected pre-localized by the app.
public struct SettingsSearchItem: Identifiable, Hashable, Sendable {
    /// Stable identifier. A content controller registers the matching control
    /// under this same id so search can scroll directly to it.
    public let id: String
    /// Owning tab id (matches a `SettingsTab.id`).
    public let tabID: String
    /// Owning section anchor id (matches a section registered by the tab).
    public let sectionAnchor: String
    /// Title shown as the primary line of the search result.
    public let title: String
    /// Localized tab title, used for the result subtitle and tab-field scoring.
    public let tabTitle: String
    /// Localized section title, used for the result subtitle.
    public let sectionTitle: String
    /// Extra terms that should match this item but aren't in the title.
    public let keywords: [String]

    public init(
        id: String,
        tabID: String,
        sectionAnchor: String,
        title: String,
        tabTitle: String,
        sectionTitle: String,
        keywords: [String] = []
    ) {
        self.id = id
        self.tabID = tabID
        self.sectionAnchor = sectionAnchor
        self.title = title
        self.tabTitle = tabTitle
        self.sectionTitle = sectionTitle
        self.keywords = keywords
    }
}

public struct SettingsSearchResult: Identifiable, Hashable, Sendable {
    public let item: SettingsSearchItem
    public let score: Int

    /// Precomputed once at init. The subtitle is read for every visible result
    /// cell on every reload/scroll-recycle; folding the strings here (instead of
    /// in the computed getter) keeps that path allocation-free. Derived purely
    /// from `item`, so it stays consistent with `Hashable`/`Equatable`.
    private let precomputedTabAndSectionTitle: String

    public init(item: SettingsSearchItem, score: Int) {
        self.item = item
        self.score = score
        self.precomputedTabAndSectionTitle = Self.makeTabAndSectionTitle(for: item)
    }

    public var id: String { item.id }

    public var sidebarDisplayText: String {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Secondary line: "Tab · Section", collapsed to a single label when the
    /// tab and section (or section and setting) titles are effectively equal.
    public var localizedTabAndSectionTitle: String { precomputedTabAndSectionTitle }

    private static func makeTabAndSectionTitle(for item: SettingsSearchItem) -> String {
        let tab = item.tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = item.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSection = normalizeLabel(section)
        let sameTabSection = !tab.isEmpty && normalizeLabel(tab) == normalizedSection
        let sameTitleSection = !section.isEmpty && normalizeLabel(title) == normalizedSection
        if sameTabSection || sameTitleSection { return tab }
        if tab.isEmpty { return section }
        if section.isEmpty { return tab }
        return "\(tab) · \(section)"
    }

    static func normalizeLabel(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
    }
}
