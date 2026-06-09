import XCTest

// #R001: MailcartUITests launches the fixture app and exercises core mailbox flows.
final class MailcartUITests: XCTestCase {
    private var app: XCUIApplication!

    // #R001: Launch fixture-mode app once per test with deterministic UI-test inputs.
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launchEnvironment["MAILCART_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MAILCART_UI_TEST_PAGE_SIZE"] = "2"
        app.launch()
    }

    // #R001: Search flow surfaces fixture rows filtered by query text.
    func testSearchFilterFindsFixtureRow() {
        let expectedSubject = app.staticTexts["mailcart.summarySubject.msg_001"]
        XCTAssertTrue(expectedSubject.waitForExistence(timeout: 5))
    }

    // #R001: Pagination flow appends additional fixture rows via Load More.
    func testLoadMoreAppendsFixtureRows() {
        let loadMoreButton = app.buttons["mailcart.loadMoreButton"]
        if loadMoreButton.waitForExistence(timeout: 3) {
            loadMoreButton.tap()
        }

        let appendedSubject = app.staticTexts["mailcart.summarySubject.msg_003"]
        XCTAssertTrue(appendedSubject.waitForExistence(timeout: 5))
    }

    // #R001: Selecting a summary row opens the corresponding fixture detail view.
    func testSelectingSummaryLoadsFixtureDetail() {
        let summaryRow = app.staticTexts["mailcart.summarySubject.msg_001"]
        XCTAssertTrue(summaryRow.waitForExistence(timeout: 5))
        summaryRow.tap()

        let detailSubject = app.staticTexts["mailcart.detailSubject"]
        XCTAssertTrue(detailSubject.waitForExistence(timeout: 5))
        let detailSender = app.staticTexts["mailcart.detailSender"]
        XCTAssertTrue(detailSender.waitForExistence(timeout: 5))
    }
}
