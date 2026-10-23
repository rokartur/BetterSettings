import XCTest
@testable import BetterSettings

@MainActor
final class SettingsRouterHistoryTests: XCTestCase {

    func testBackAndForwardWalkVisitedTabs() {
        let router = SettingsRouter(selectedTabID: "a")
        router.selectedTabID = "b"
        router.selectedTabID = "c"

        router.goBack()
        XCTAssertEqual(router.selectedTabID, "b")
        router.goBack()
        XCTAssertEqual(router.selectedTabID, "a")
        XCTAssertFalse(router.canGoBack)

        router.goForward()
        XCTAssertEqual(router.selectedTabID, "b")
        XCTAssertTrue(router.canGoForward)
    }

    func testNewTabAfterGoingBackDropsForwardHistory() {
        let router = SettingsRouter(selectedTabID: "a")
        router.selectedTabID = "b"
        router.goBack()
        router.selectedTabID = "c"

        XCTAssertFalse(router.canGoForward)
        XCTAssertEqual(router.history, ["a", "c"])
    }

    func testReselectingTheShownTabAddsNoEntry() {
        let router = SettingsRouter(selectedTabID: "a")
        router.navigateToTabTop("a")
        XCTAssertFalse(router.canGoBack)
    }
}
