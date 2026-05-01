//  ReaderBottomBarHoldUITest.swift
//  Holds the reader on screen so the host can capture the bottom bar layout.

import XCTest

final class ReaderBottomBarHoldUITest: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testHoldOnReaderForBottomBarCapture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let bookHit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Metamorphosis")).firstMatch
        XCTAssertTrue(bookHit.waitForExistence(timeout: 6))
        bookHit.tap()
        XCTAssertTrue(app.buttons["Start RSVP from current word"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 30)
    }
}
