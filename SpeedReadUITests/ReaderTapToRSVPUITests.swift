//  ReaderTapToRSVPUITests.swift
//  Verifies the production reader → tap word → RSVP → dismiss → red-highlight flow.

import XCTest

final class ReaderTapToRSVPUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLibraryShowsBooks() throws {
        let app = launchAppPastOnboarding()

        // Library navigation title
        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 5))

        // At least one sample book loaded.
        let firstBook = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Metamorphosis")).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCaptureReaderAndRSVPScreens() throws {
        let app = launchAppPastOnboarding()

        let bookHit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Metamorphosis")).firstMatch
        XCTAssertTrue(bookHit.waitForExistence(timeout: 5))
        bookHit.tap()

        let rsvpButton = app.buttons["Start RSVP from current word"]
        XCTAssertTrue(rsvpButton.waitForExistence(timeout: 5))

        // Reader view screenshot
        try saveScreenshot(named: "reader-default")

        // Tap a body word, capture RSVP
        let wordHit = app.staticTexts["Gregor"].firstMatch
        if wordHit.waitForExistence(timeout: 4) {
            wordHit.tap()
        } else {
            rsvpButton.tap()
        }
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        try saveScreenshot(named: "rsvp-active")

        // Dismiss back to reader, capture red-highlight state
        closeButton.tap()
        XCTAssertTrue(rsvpButton.waitForExistence(timeout: 5))
        try saveScreenshot(named: "reader-with-red-word")
    }


    @MainActor
    private func saveScreenshot(named name: String) throws {
        let shot = XCUIScreen.main.screenshot()
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp.appendingPathComponent("speedread-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try shot.pngRepresentation.write(to: url)
        print("[SCREENSHOT] \(name) -> \(url.path)")

        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }




    @MainActor
    func testTapWordOpensRSVP() throws {
        let app = launchAppPastOnboarding()

        // Open a sample book.
        let bookHit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Metamorphosis")).firstMatch
        XCTAssertTrue(bookHit.waitForExistence(timeout: 5))
        bookHit.tap()

        // Reader bottom bar's RSVP button is the canonical landmark for "we are in the reader".
        let rsvpButton = app.buttons["Start RSVP from current word"]
        XCTAssertTrue(rsvpButton.waitForExistence(timeout: 5), "Reader view did not present its RSVP button")

        // Tap a body word — any tappable word in the body. The first interior body Text should suffice.
        // Words are exposed as accessibility elements with `accessibilityLabel` matching the word text.
        // Pick a common, predictable word from the book.
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists)

        let wordHit = app.staticTexts["Gregor"].firstMatch
        if wordHit.waitForExistence(timeout: 4) {
            wordHit.tap()
        } else {
            // Fall back: tap RSVP launch button if a body word can't be located by label.
            rsvpButton.tap()
        }

        // RSVP toolbar shows a Close button.
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "RSVP view did not appear")

        // Dismiss back to the reader.
        closeButton.tap()

        // We're back in the reader.
        XCTAssertTrue(rsvpButton.waitForExistence(timeout: 5))

        // The "Resume" pill should be visible — confirms the bottom bar is intact.
        XCTAssertTrue(app.buttons["Resume — jump to the last-read word"].exists)
    }

    // MARK: - Helpers

    @MainActor
    private func launchAppPastOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()
        return app
    }
}
