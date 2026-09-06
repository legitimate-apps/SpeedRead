import XCTest

final class OnboardingUITests: XCTestCase {
    /// Onboarding is the first screen every new reader sees, and until this test every other UI
    /// test skipped it with `-hasCompletedOnboarding YES`. Paging is a UIPageViewController fact,
    /// so a unit test cannot reach it — see TDD-MISSION.md §5af–§5ah.
    @MainActor
    func testNewReaderPagesThroughOnboardingAndOpensLibrary() throws {
        continueAfterFailure = false

        // `--reset-onboarding` CLEARS the persisted flag (DEBUG only). The obvious alternative,
        // `-hasCompletedOnboarding NO`, makes the test repeatable and simultaneously unable to
        // prove anything: the argument domain outranks the persistent domain on read, so the write
        // that completing onboarding performs stays masked and the app never leaves onboarding.
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to SpeedRead"].waitForExistence(timeout: 8))
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.staticTexts["One word at a time"].waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.staticTexts["Your shelf is ready"].waitForExistence(timeout: 5))

        let openLibrary = app.buttons["Open Your Library"]
        XCTAssertTrue(openLibrary.isHittable)
        openLibrary.tap()
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 8))
        app.terminate()

        // Relaunch with no override at all: completion has to have been persisted for real.
        let returning = XCUIApplication()
        returning.launchArguments = []
        returning.launch()
        XCTAssertTrue(returning.navigationBars["Your Library"].waitForExistence(timeout: 8),
                      "A returning reader must not be shown onboarding again")
        returning.terminate()
    }
}
