//  WatchSyncUITests.swift
//  Drives the iPhone's "Send to Watch" path so a paired Watch sim receives a book.

import XCTest

final class WatchSyncUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendFirstBookToWatch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Your Library"].waitForExistence(timeout: 5))

        // Long-press a book spine to bring up the context menu.
        let bookHit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Metamorphosis")).firstMatch
        XCTAssertTrue(bookHit.waitForExistence(timeout: 5))
        bookHit.press(forDuration: 1.2)

        // The context menu Button is exposed by Label("Send to Watch", systemImage: ...)
        let sendButton = app.buttons["Send to Watch"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Send to Watch button never appeared")
        sendButton.tap()

        // Sit on the screen long enough for WCSession to deliver the message.
        Thread.sleep(forTimeInterval: 6)
    }
}
