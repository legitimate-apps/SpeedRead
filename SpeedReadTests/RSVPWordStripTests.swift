import CoreGraphics
import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("RSVP word strip")
struct RSVPWordStripTests {
    private let word = RSVPWordStripLayout.Word(before: 20, focus: 10, after: 30)

    private func layout(offset: CGFloat, previous: Int = 2, next: Int = 2) -> RSVPWordStripLayout {
        RSVPWordStripLayout(
            current: word,
            previous: Array(repeating: .init(before: 10, focus: 10, after: 20), count: previous),
            next: Array(repeating: .init(before: 30, focus: 10, after: 10), count: next),
            space: 12,
            offset: offset
        )
    }

    // MARK: - Neighbors

    @Test func theStripTakesTheNearestWordsEitherSide() {
        let words = (0..<20).map { "w\($0)" }
        let strip = RSVPWordStrip(words: words, index: 10, offset: 0.2, opacity: 1)
        #expect(strip.previous == ["w9", "w8", "w7", "w6"])
        #expect(strip.next == ["w11", "w12", "w13", "w14"])
        #expect(strip.offset == 0.2)

        let start = RSVPWordStrip(words: words, index: 0, offset: 0, opacity: 1)
        #expect(start.previous.isEmpty)
        #expect(start.next.count == RSVPWordStrip.neighborCount)
        let end = RSVPWordStrip(words: words, index: 19, offset: 0, opacity: 1)
        #expect(end.next.isEmpty)
        #expect(RSVPWordStrip(words: words, index: 20, offset: 0, opacity: 1) == RSVPWordStrip())
        #expect(RSVPWordStrip(words: [], index: 0, offset: 0, opacity: 1) == RSVPWordStrip())
    }

    // MARK: - Geometry

    @Test func neighborsSitOneSpaceAwayWithoutOverlapping() {
        let strip = layout(offset: 0)
        // Current word spans -25...35 around its pivot.
        #expect(strip.currentLeadingEdge == -25)
        // Each previous word is 40 wide, each next word 50, with a 12-point space between.
        let previousEdges: [CGFloat] = [-77, -129]
        let nextEdges: [CGFloat] = [47, 109]
        #expect(strip.previousLeadingEdges == previousEdges)
        #expect(strip.nextLeadingEdges == nextEdges)
        #expect(strip.shift == 0)
    }

    @Test func aFullWordOfDragPutsTheNeighborsPivotOnTheGuides() {
        // Mutation: shift by the neighbor's leading edge instead of its pivot. The strip would
        // then jump at every word change.
        let forward = layout(offset: 1)
        let nextPivot = forward.nextLeadingEdges[0] + forward.next[0].focusCenter
        #expect(nextPivot + forward.shift == 0)

        let backward = layout(offset: -1)
        let previousPivot = backward.previousLeadingEdges[0] + backward.previous[0].focusCenter
        #expect(previousPivot + backward.shift == 0)
    }

    @Test func theStripFollowsTheFingerAndIsContinuousAcrossAWordChange() {
        // Dragging left moves the strip left (negative shift) and brings the next word in from the right.
        #expect(layout(offset: 0.4).shift < 0)
        #expect(layout(offset: -0.4).shift > 0)
        // Halfway to the next word, then halfway back from it once it is current: the same place.
        let before = layout(offset: 0.5)
        let nextPivotBefore = before.nextLeadingEdges[0] + before.next[0].focusCenter + before.shift
        let after = RSVPWordStripLayout(
            current: before.next[0], previous: [word], next: [], space: 12, offset: -0.5)
        let oldPivotAfter = after.previousLeadingEdges[0] + after.previous[0].focusCenter + after.shift
        // Both words are drawn where they were a frame earlier.
        #expect(abs(after.shift - nextPivotBefore) < 0.0001)
        #expect(abs(oldPivotAfter - before.shift) < 0.0001)
    }

    @Test func theStripDoesNotMoveTowardAWordThatIsNotThere() {
        #expect(layout(offset: 0.4, next: 0).shift == 0)
        #expect(layout(offset: -0.4, previous: 0).shift == 0)
    }

    @Test func wordsFadeWithDistanceFromTheGuidesAndVanishAtTheEdge() {
        let strip = layout(offset: 0)
        #expect(strip.alpha(atFocusX: 0, halfWidth: 180) == 1)
        let neighbor = strip.alpha(atFocusX: strip.step, halfWidth: 180)
        #expect(abs(neighbor - RSVPWordStripLayout.neighborAlpha) < 0.0001)
        #expect(strip.alpha(atFocusX: -strip.step / 2, halfWidth: 180) > neighbor)
        #expect(strip.alpha(atFocusX: 150, halfWidth: 180) < neighbor)
        #expect(strip.alpha(atFocusX: 180, halfWidth: 180) == 0)
        #expect(strip.alpha(atFocusX: 0, halfWidth: 0) == 0)
    }

    @Test func theRedPivotHandsOverAtTheHalfwayPoint() {
        #expect(RSVPWordStripLayout.pivotAlpha(offset: 0, stripOpacity: 1) == 1)
        #expect(RSVPWordStripLayout.pivotAlpha(offset: 0.25, stripOpacity: 1) == 0.5)
        #expect(RSVPWordStripLayout.pivotAlpha(offset: -0.5, stripOpacity: 1) == 0)
        // Not dragging: the pivot is the plain RSVP pivot whatever the offset.
        #expect(RSVPWordStripLayout.pivotAlpha(offset: 0.5, stripOpacity: 0) == 1)
    }

    // MARK: - Caption

    @Test func theCaptionSaysHowFarAndWhichWay() {
        #expect(RSVPScrubCaption.text(from: 10, to: 10) == nil)
        #expect(RSVPScrubCaption.text(from: 10, to: 11) == "1 word ahead")
        #expect(RSVPScrubCaption.text(from: 10, to: 51) == "41 words ahead")
        #expect(RSVPScrubCaption.text(from: 10, to: 9) == "1 word back")
        #expect(RSVPScrubCaption.text(from: 40, to: 28) == "12 words back")
        #expect(RSVPScrubCaption.direction(from: 3, to: 4) == .ahead)
        #expect(RSVPScrubCaption.direction(from: 4, to: 3) == .back)
    }
}
