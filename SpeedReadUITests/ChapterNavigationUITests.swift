import XCTest
import UIKit

final class ChapterNavigationUITests: XCTestCase {
    @MainActor
    func testChapterJumpShowsCurrentChapterAndRSVPWhileResumeKeepsPlace() throws {
        // Mutations: omit menu/sheet, commit jump, omit scroll, mark last-read rather than browse, use last-read RSVP chapter.
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--chapter-ui-fixture"]
        app.launch()
        let menu = app.buttons["Reader menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["Chapters"].tap()
        let opening = app.buttons["Opening chapter"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        XCTAssertEqual(opening.value as? String, "Current chapter")
        try capture("chapters-present")
        app.buttons["Destination chapter"].tap()
        let destination = app.buttons["Destination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isHittable, "Chapter jump must actually scroll to its word")
        menu.tap()
        app.buttons["Chapters"].tap()
        XCTAssertEqual(app.buttons["Destination chapter"].value as? String, "Current chapter")
        app.buttons["Close chapters"].tap()
        app.buttons["Start RSVP from current word"].tap()
        let chapter = app.staticTexts["rsvp-current-chapter"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        XCTAssertEqual(chapter.label, "Current chapter: Destination chapter")
        let surface = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        surface.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        XCTAssertEqual(chapter.label, "Current chapter: Opening chapter")
        try capture("rsvp-chapter-scrub")
        app.buttons["Close"].tap()
        app.buttons["Resume — jump to the last-read word"].tap()
        menu.tap()
        app.buttons["Chapters"].tap()
        XCTAssertEqual(app.buttons["Opening chapter"].value as? String, "Current chapter")
    }

    @MainActor
    func testChapterlessBookOmitsEntryAndRSVPLabel() throws {
        // Mutations: show a disabled/empty Chapters entry, fabricate an RSVP chapter for unstructured text.
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--chapter-ui-fixture", "--chapter-ui-empty"]
        app.launch()
        let menu = app.buttons["Reader menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertTrue(app.buttons["Bookmarks"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Chapters"].exists)
        try capture("chapters-absent")
        app.buttons["Bookmarks"].tap()
        app.buttons["Close"].tap()
        app.buttons["Start RSVP from current word"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rsvp-current-chapter"].exists)
    }

    @MainActor
    private func capture(_ name: String) throws {
        let image = XCUIScreen.main.screenshot().image
        let size = CGSize(width: image.size.width * 600 / image.size.height, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let data = try XCTUnwrap(resized.jpegData(compressionQuality: 0.35))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leg31-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".jpg")
        try data.write(to: url)
        print("[CHAPTER-SCREENSHOT] \(url.path)")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
