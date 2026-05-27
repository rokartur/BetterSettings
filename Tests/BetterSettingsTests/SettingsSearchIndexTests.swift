import XCTest
@testable import BetterSettings

final class SettingsSearchIndexTests: XCTestCase {

    private func makeIndex() -> SettingsSearchIndex {
        SettingsSearchIndex(items: [
            SettingsSearchItem(id: "general.launchAtLogin", tabID: "general", sectionAnchor: "general.behavior",
                               title: "Launch at login", tabTitle: "General", sectionTitle: "Behavior",
                               keywords: ["startup", "boot"]),
            SettingsSearchItem(id: "general.menuBar", tabID: "general", sectionAnchor: "general.behavior",
                               title: "Show in menu bar", tabTitle: "General", sectionTitle: "Behavior",
                               keywords: ["status item", "tray"]),
            SettingsSearchItem(id: "appearance.mode", tabID: "appearance", sectionAnchor: "appearance.theme",
                               title: "Appearance", tabTitle: "Appearance", sectionTitle: "Theme",
                               keywords: ["dark mode", "light mode"]),
        ])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(makeIndex().search(query: "").isEmpty)
        XCTAssertTrue(makeIndex().search(query: "   ").isEmpty)
    }

    func testTitlePrefixMatch() {
        let results = makeIndex().search(query: "launch")
        XCTAssertEqual(results.first?.item.id, "general.launchAtLogin")
    }

    func testKeywordMatch() {
        let results = makeIndex().search(query: "tray")
        XCTAssertEqual(results.first?.item.id, "general.menuBar")
    }

    func testTitleBeatsKeyword() {
        // "Appearance" title match must outrank any keyword-only match.
        let results = makeIndex().search(query: "appearance")
        XCTAssertEqual(results.first?.item.id, "appearance.mode")
    }

    func testAllTokensMustMatch() {
        // "menu bar" both tokens hit the menu-bar item; "menu xyz" matches none.
        XCTAssertEqual(makeIndex().search(query: "menu bar").first?.item.id, "general.menuBar")
        XCTAssertTrue(makeIndex().search(query: "menu zzzznotaterm").isEmpty)
    }

    func testDiacriticAndCaseInsensitive() {
        XCTAssertEqual(makeIndex().search(query: "LÄUNCH").first?.item.id, "general.launchAtLogin")
    }

    func testTabAndSectionSubtitleCollapsesWhenEqual() {
        let result = SettingsSearchResult(
            item: SettingsSearchItem(id: "x", tabID: "t", sectionAnchor: "a",
                                     title: "Some setting", tabTitle: "Audio", sectionTitle: "Audio"),
            score: 1
        )
        XCTAssertEqual(result.localizedTabAndSectionTitle, "Audio")
    }

    func testTabAndSectionSubtitleJoinsWhenDifferent() {
        let result = SettingsSearchResult(
            item: SettingsSearchItem(id: "x", tabID: "t", sectionAnchor: "a",
                                     title: "Some setting", tabTitle: "General", sectionTitle: "Behavior"),
            score: 1
        )
        XCTAssertEqual(result.localizedTabAndSectionTitle, "General · Behavior")
    }
}
