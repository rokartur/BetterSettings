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
    @Published public var selectedTabID: String
    @Published public var navigationRequest: SettingsNavigationRequest?

    public init(selectedTabID: String) {
        self.selectedTabID = selectedTabID
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
