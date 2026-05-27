//
//  SettingsSearchIndex.swift
//  BetterSettings
//
//  Token-scoring search over the settings catalog. Ranks title matches above
//  keyword matches above tab matches, and word-prefix matches above
//  mid-word substring matches, so the most relevant setting sorts first.
//
//  All query tokens must match (AND semantics) for an item to appear.
//

import Foundation

public struct SettingsSearchIndex: Sendable {
    private let documents: [(item: SettingsSearchItem, doc: SearchDocument)]

    public init(items: [SettingsSearchItem]) {
        // Catalog order is authoritative: apps list items in interface order.
        self.documents = items.map { ($0, SearchDocument(item: $0)) }
    }

    public func search(query: String) -> [SettingsSearchResult] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return [] }

        var matches: [SettingsSearchResult] = []
        matches.reserveCapacity(documents.count)

        for entry in documents {
            let document = entry.doc

            var totalScore = 0
            var allMatched = true
            for token in queryTokens {
                let tokenScore = scoreForToken(token, in: document)
                if tokenScore == 0 {
                    allMatched = false
                    break
                }
                totalScore += tokenScore
            }
            guard allMatched else { continue }

            // Whole-query bonus rewards items where the full phrase appears.
            if Self.containsWordPrefix(in: document.titleFields, token: normalizedQuery) {
                totalScore += 60
            } else if Self.containsSubstring(in: document.titleFields, token: normalizedQuery) {
                totalScore += 35
            } else if Self.containsWordPrefix(in: document.keywordFields, token: normalizedQuery) {
                totalScore += 24
            } else if Self.containsSubstring(in: document.keywordFields, token: normalizedQuery) {
                totalScore += 14
            }

            matches.append(SettingsSearchResult(item: entry.item, score: totalScore))
        }

        // Stable sort: higher score first, ties keep catalog order.
        return matches
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score {
                    return lhs.element.score > rhs.element.score
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func scoreForToken(_ token: String, in document: SearchDocument) -> Int {
        if Self.containsWordPrefix(in: document.titleFields, token: token) { return 420 }
        if Self.containsSubstring(in: document.titleFields, token: token) { return 330 }
        if Self.containsWordPrefix(in: document.keywordFields, token: token) { return 240 }
        if Self.containsSubstring(in: document.keywordFields, token: token) { return 170 }
        if Self.containsWordPrefix(in: document.tabFields, token: token) { return 120 }
        if Self.containsSubstring(in: document.tabFields, token: token) { return 90 }
        return 0
    }

    private static func containsSubstring(in fields: [String], token: String) -> Bool {
        fields.contains { $0.contains(token) }
    }

    private static func containsWordPrefix(in fields: [String], token: String) -> Bool {
        fields.contains { field in
            field.split(separator: " ").contains { $0.hasPrefix(token) }
        }
    }

    /// Case/diacritic/width-insensitive, whitespace-collapsed normalization.
    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
    }
}

private struct SearchDocument: Sendable {
    let titleFields: [String]
    let keywordFields: [String]
    let tabFields: [String]

    init(item: SettingsSearchItem) {
        self.titleFields = SearchDocument.normalizedVariants([item.title])
        self.keywordFields = SearchDocument.normalizedVariants(item.keywords)
        self.tabFields = SearchDocument.normalizedVariants([item.tabTitle, item.sectionTitle])
    }

    private static func normalizedVariants(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        output.reserveCapacity(values.count)
        for value in values {
            let normalized = SettingsSearchIndex.normalize(value)
            if !normalized.isEmpty, seen.insert(normalized).inserted {
                output.append(normalized)
            }
        }
        return output
    }
}
