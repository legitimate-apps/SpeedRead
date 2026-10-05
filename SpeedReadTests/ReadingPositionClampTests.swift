import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("Position clamp boundaries")
@MainActor
struct ReadingPositionClampTests {
    @Test(arguments: [-1, 0, 1, 100])
    func canonicalEmptyAndSingleWordBoundaries(index: Int) {
        // Mutation: remove the empty-count guard, lower bound, or final-word subtraction.
        #expect(ReadingPositionCoordinator.clampedIndex(index, wordCount: 0) == 0)
        #expect(ReadingPositionCoordinator.clampedIndex(index, wordCount: 1) == 0)
    }

    @Test(arguments: [-100, 100])
    func engineLoadAndSeekClampBothSides(index: Int) {
        // Mutation: replace either load/seek clamp with the raw index or a one-sided clamp.
        let engine = RSVPEngine()
        let expected = index < 0 ? 0 : 2
        engine.load(words: ["zero", "one", "two"], startingAt: index)
        #expect(engine.currentIndex == expected)
        #expect(engine.currentWord == (expected == 0 ? "zero" : "two"))
        engine.seek(to: 1)
        engine.seek(to: index)
        #expect(engine.currentIndex == expected)
        #expect(engine.currentWord == (expected == 0 ? "zero" : "two"))
    }

    #if os(iOS)
    @Test(arguments: [-800.0, 800.0])
    func scrubClampsBothSides(translation: Double) throws {
        // Mutation: remove either side of the gesture target clamp.
        let session = RSVPPresentationSession()
        let update = try #require(session.updateGesture(
            translationX: translation, at: 0, isPlaying: false, currentIndex: 1, wordCount: 3,
            track: RSVPScrubTrack(words: ["zero", "one", "two"], advance: 20, availableWidth: 400)))
        #expect(update.targetIndex == (translation < 0 ? 2 : 0))
    }

    #endif
}
