import XCTest

// #R001: MailcartTests validates launch-mode behavior used by app bootstrap.
final class MailcartTests: XCTestCase {
    // #R001: `--ui-testing` launch arg forces UI-testing mode.
    func testDetectLaunchModeUsesUITestingArgument() {
        let mode = detectMailcartLaunchMode(arguments: ["mailcart", "--ui-testing"], environment: [:])
        XCTAssertEqual(mode, .uiTesting)
    }

    // #R001: fixture-mode env var forces UI-testing mode.
    func testDetectLaunchModeUsesUITestingEnvironment() {
        let mode = detectMailcartLaunchMode(
            arguments: ["mailcart"],
            environment: ["MAILCART_UI_TEST_MODE": "1"]
        )
        XCTAssertEqual(mode, .uiTesting)
    }

    // #R001: normal launches remain in production mode.
    func testDetectLaunchModeDefaultsToNormal() {
        let mode = detectMailcartLaunchMode(arguments: ["mailcart"], environment: [:])
        XCTAssertEqual(mode, .normal)
    }
}
