import XCTest

final class MailcartUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 5

    private func firstVisibleSummaryIdentifier() -> String? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "mailcart.summarySubject.")
        let query = app.descendants(matching: .staticText).matching(predicate)
        let maxCount = min(query.count, 12)
        for index in 0..<maxCount {
            let element = query.element(boundBy: index)
            if element.exists && element.isHittable {
                return element.identifier
            }
        }
        return nil
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launchEnvironment["MAILCART_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MAILCART_UI_TEST_PAGE_SIZE"] = "2"
        app.launch()
    }

    func testSearchFilterFindsFixtureRow() {
        let searchField = app.textFields["mailcart.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.click()
        searchField.typeText("airline")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["Airline Luggage Fee confirmation"].waitForExistence(timeout: timeout))
    }

    func testLoadMoreAppendsFixtureRows() {
        XCTAssertTrue(app.staticTexts["Coffee Roasters weekly update"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["City Transit Card refill notice"].exists)

        let loadMoreButton = app.buttons["mailcart.loadMoreButton"]
        XCTAssertTrue(loadMoreButton.waitForExistence(timeout: timeout))
        loadMoreButton.click()

        XCTAssertTrue(app.staticTexts["City Transit Card refill notice"].waitForExistence(timeout: timeout))
    }

    func testSelectingSummaryLoadsFixtureDetail() {
        let rowLabel = app.staticTexts["Coffee Roasters weekly update"]
        XCTAssertTrue(rowLabel.waitForExistence(timeout: timeout))
        rowLabel.click()

        XCTAssertTrue(app.staticTexts["Coffee Roasters weekly update"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["From: coffee@example.com"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["To: user@example.com"].waitForExistence(timeout: timeout))
    }

    func testSortDetailAndBodyModesWorkInSingleLaunch() {
        let loadMoreButton = app.buttons["mailcart.loadMoreButton"]
        XCTAssertTrue(loadMoreButton.waitForExistence(timeout: timeout))
        loadMoreButton.click()
        XCTAssertTrue(app.staticTexts["Airline Luggage Fee confirmation"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["City Transit Card refill notice"].waitForExistence(timeout: timeout))

        let subjectSortButton = app.descendants(matching: .any).matching(identifier: "mailcart.sortSubject").firstMatch
        XCTAssertTrue(subjectSortButton.waitForExistence(timeout: timeout))
        subjectSortButton.click()
        XCTAssertEqual(firstVisibleSummaryIdentifier(), "mailcart.summarySubject.msg_004")

        let dateSortButton = app.descendants(matching: .any).matching(identifier: "mailcart.sortDate").firstMatch
        XCTAssertTrue(dateSortButton.waitForExistence(timeout: timeout))
        dateSortButton.click()
        XCTAssertEqual(firstVisibleSummaryIdentifier(), "mailcart.summarySubject.msg_001")

        let coffeeRow = app.staticTexts["Coffee Roasters weekly update"]
        XCTAssertTrue(coffeeRow.waitForExistence(timeout: timeout))
        coffeeRow.click()
        XCTAssertTrue(app.staticTexts["From: coffee@example.com"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["To: user@example.com"].waitForExistence(timeout: timeout))

        let searchField = app.textFields["mailcart.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        searchField.typeText("city")
        app.typeKey(.return, modifierFlags: [])

        let cityRow = app.staticTexts["City Transit Card refill notice"]
        XCTAssertTrue(cityRow.waitForExistence(timeout: timeout))
        cityRow.click()
        XCTAssertTrue(app.staticTexts["mailcart.detailSubject"].waitForExistence(timeout: timeout))
        // swiftlint:disable:next line_length
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mailcart.renderedBody").firstMatch.waitForExistence(timeout: timeout))

        let renderedMode = app.descendants(matching: .any).matching(identifier: "mailcart.bodyModeRendered").firstMatch
        XCTAssertTrue(renderedMode.waitForExistence(timeout: timeout))
        renderedMode.click()
        // swiftlint:disable:next line_length
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mailcart.renderedBody").firstMatch.waitForExistence(timeout: timeout))

        let rawMode = app.descendants(matching: .any).matching(identifier: "mailcart.bodyModeRaw").firstMatch
        XCTAssertTrue(rawMode.waitForExistence(timeout: timeout))
        rawMode.click()
        let rawBody = app.staticTexts["mailcart.rawBodyText"]
        XCTAssertTrue(rawBody.waitForExistence(timeout: timeout))
        let rawHtmlText = app.staticTexts["<p>Your transit card <em>auto-refill</em> is scheduled.</p>"]
        XCTAssertTrue(rawHtmlText.waitForExistence(timeout: timeout))
    }

    func testSearchFieldAcceptsTyping() {
        let searchField = app.textFields["mailcart.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.click()
        searchField.typeText("ui-regression-query")
    }

    func testLoadMoreButtonExistsAndCanBeTapped() {
        let loadMoreButton = app.buttons["mailcart.loadMoreButton"]
        XCTAssertTrue(loadMoreButton.waitForExistence(timeout: timeout))
        loadMoreButton.click()
    }

    func testSummaryListIsVisible() {
        let summaryList = app.descendants(matching: .any).matching(identifier: "mailcart.summaryList").firstMatch
        XCTAssertTrue(summaryList.waitForExistence(timeout: timeout))
    }
}
