import XCTest

/// Walks the path a user actually takes on the watch: library -> tap Now Reading -> RSVP presents.
/// The crown-direction test launches straight into RSVP through a fixture and never touches this
/// path, which is how a phantom sheet shipped unnoticed.
@MainActor
final class NowReadingOpensRSVPUITests: XCTestCase {
    func testTappingNowReadingPresentsTheRSVPSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-seeded-library"]
        app.launch()

        let nowReading = app.buttons["watch-now-reading"].firstMatch
        XCTAssertTrue(nowReading.waitForExistence(timeout: 5), "Now Reading row must be visible")
        nowReading.tap()

        let position = app.descendants(matching: .any)["watch-rsvp-position"]
        XCTAssertTrue(
            position.waitForExistence(timeout: 5),
            "Tapping Now Reading must present the RSVP surface with a word position"
        )
    }

    /// The paused surface lays its controls out at the word view's width. When that width exceeds
    /// the screen, the Settings gear is pushed past the right edge: present in the tree, drawn
    /// nowhere, tappable by nobody. Found on Series 10 46mm at x=211 of a 208pt screen.
    func testSettingsControlIsOnScreenWhenPaused() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-seeded-library"]
        app.launch()

        let nowReading = app.buttons["watch-now-reading"].firstMatch
        XCTAssertTrue(nowReading.waitForExistence(timeout: 5))
        nowReading.tap()

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings control must exist")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(
            screen.contains(settings.frame),
            "Settings control must lie within the screen, got \(settings.frame) in \(screen)"
        )
        XCTAssertTrue(settings.isHittable, "Settings control must be hittable")
    }
}
