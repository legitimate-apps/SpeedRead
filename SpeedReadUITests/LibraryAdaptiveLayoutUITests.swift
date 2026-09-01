import XCTest

final class LibraryAdaptiveLayoutUITests: XCTestCase {
    // XCUIDevice.orientation is PROCESS-WIDE and survives the test that set it, so without this
    // the next test class starts in landscape. A trailing Thread.sleep used to mask it by letting
    // the simulator settle before the suite moved on; removing that sleep (it made this a capture
    // holder) exposed the real defect underneath. Restoring state belongs in teardown, not in a
    // sleep at the end of the happy path.
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    @MainActor
    func testLibrarySupportsPortraitAndLandscape() throws {
        let device = XCUIDevice.shared
        device.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 8))
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "library-ipad-portrait"
        portrait.lifetime = .keepAlways
        add(portrait)

        device.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 3))
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "library-ipad-landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
    }
}
