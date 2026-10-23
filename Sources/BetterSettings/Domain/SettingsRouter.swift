//
//  SettingsRouter.swift
//  BetterSettings
//
//  Single source of truth for which tab is shown and for one-shot navigation
//  requests (sidebar tab clicks and search-result jumps). The split view
//  observes `selectedTabID`; the content controller observes `navigationRequest`.
//

import Foundation
import Combine

/// One navigation intent. `requestID` makes otherwise-equal requests distinct
/// so re-selecting the same target still fires (and so a request is handled once).
public struct SettingsNavigationRequest: Sendable, Equatable {
    public let tabID: String
    public let sectionAnchor: String?
    public let searchItemID: String?
    public let requestID: UUID

    public init(tabID: String, sectionAnchor: String?, searchItemID: String?, requestID: UUID = UUID()) {
        self.tabID = tabID
        self.sectionAnchor = sectionAnchor
        self.searchItemID = searchItemID
        self.requestID = requestID
    }
}

@MainActor
public final class SettingsRouter: ObservableObject {
    @Published public var selectedTabID: String {
        didSet { recordInHistory(selectedTabID) }
    }
    @Published public var navigationRequest: SettingsNavigationRequest?

    /// Visited tabs, oldest first; `historyIndex` points at the shown one.
    private(set) var history: [String]
    @Published public private(set) var historyIndex = 0

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    public init(selectedTabID: String) {
        self.selectedTabID = selectedTabID
        self.history = [selectedTabID]
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        selectedTabID = history[historyIndex]
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        selectedTabID = history[historyIndex]
    }

    private func recordInHistory(_ tabID: String) {
        guard history[historyIndex] != tabID else { return }
        history.removeSubrange((historyIndex + 1)...)
        history.append(tabID)
        historyIndex += 1
    }

    /// Selects a tab and scrolls it to the top.
    public func navigateToTabTop(_ tabID: String) {
        if selectedTabID != tabID {
            selectedTabID = tabID
        }
        navigationRequest = SettingsNavigationRequest(
            tabID: tabID,
            sectionAnchor: nil,
            searchItemID: nil
        )
    }

    /// Selects the owning tab and scrolls to (and highlights) the matched setting.
    public func navigateToSearchResult(_ result: SettingsSearchResult) {
        selectedTabID = result.item.tabID
        navigationRequest = SettingsNavigationRequest(
            tabID: result.item.tabID,
            sectionAnchor: result.item.sectionAnchor,
            searchItemID: result.item.id
        )
    }
}
