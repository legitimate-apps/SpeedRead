import XCTest

final class LibraryAdaptiveLayoutUITests: XCTestCase {
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

        // Keep the orientation stable briefly so command-line screenshot
        // verification can capture the same live state without opening Simulator.
        Thread.sleep(forTimeInterval: 5)
    }
}
