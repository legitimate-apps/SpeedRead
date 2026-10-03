import XCTest

@MainActor
final class CrownDirectionUITests: XCTestCase {
    func testPositiveCrownMovesBackwardAndNegativeMovesForward() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-crown-direction"]
        app.launch()

        let position = app.descendants(matching: .any)["watch-rsvp-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), "RSVP position must be visible")
        let initial = wordIndex(of: position)

        // This inversion is a product decision from the operator's 2026-08-29
        // report, not a watchOS platform convention. The original direct mapping
        // advanced on a positive delta; the operator explicitly asked SpeedRead
        // to reverse it. Do not "correct" these expectations back to direct mapping.
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.25)
        let afterPositive = waitForChangedIndex(of: position, from: initial)
        XCTAssertLessThan(
            afterPositive,
            initial,
            "A positive crown delta must move backward through the book"
        )

        XCUIDevice.shared.rotateDigitalCrown(delta: -0.25)
        let afterNegative = waitForChangedIndex(of: position, from: afterPositive)
        XCTAssertGreaterThan(
            afterNegative,
            afterPositive,
            "A negative crown delta must move forward through the book"
        )
    }

    /// The crown binding is not written during playback (it made watchOS rebuild detents across
    /// the whole book per word), so pausing must catch it up. If it does not, the first turn
    /// measures its delta from the stale pre-playback value and snaps back to where reading began.
    func testCrownAfterPlaybackMovesFromThePausedWord() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-crown-direction", "-rsvpLastWPM", "1000"]
        app.launch()

        let position = app.descendants(matching: .any)["watch-rsvp-position"]
        let toggle = app.buttons["rsvp-playback-toggle"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), "RSVP position must be visible")
        let start = wordIndex(of: position)

        toggle.tap()
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let value = (object as? XCUIElement)?.value as? String,
                      let index = Int(value) else { return false }
                return index >= start + 40
            },
            object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
        toggle.tap()
        let paused = wordIndex(of: position)
        XCTAssertGreaterThanOrEqual(paused, start + 40)

        XCUIDevice.shared.rotateDigitalCrown(delta: 0.25)
        let afterTurn = waitForChangedIndex(of: position, from: paused)

        XCTAssertLessThan(afterTurn, paused, "A positive delta still moves backward")
        XCTAssertGreaterThan(
            afterTurn,
            start + (paused - start) / 2,
            "The first turn after playback must move from the paused word, not snap back toward \(start)"
        )
    }

    private func waitForChangedIndex(
        of element: XCUIElement,
        from original: Int
    ) -> Int {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement,
                      let value = element.value as? String,
                      let index = Int(value) else { return false }
                return index != original
            },
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        return wordIndex(of: element)
    }

    private func wordIndex(of element: XCUIElement) -> Int {
        guard let value = element.value as? String,
              let index = Int(value) else {
            XCTFail("RSVP position value must be an integer, got \(String(describing: element.value))")
            return -1
        }
        return index
    }
}
