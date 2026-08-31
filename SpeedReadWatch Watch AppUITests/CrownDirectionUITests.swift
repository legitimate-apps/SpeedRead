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
