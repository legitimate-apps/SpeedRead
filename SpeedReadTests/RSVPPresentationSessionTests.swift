import Foundation
import Testing
@testable import SpeedRead

@Suite("RSVP presentation session")
@MainActor
struct RSVPPresentationSessionTests {
    @Test("B4: a new gesture cannot inherit velocity from the previous gesture")
    func newGestureResetsItsVelocityBaseline() throws {
        let session = RSVPPresentationSession()
        let firstTime = Date(timeIntervalSince1970: 1_000)

        let first = try #require(session.updateGesture(
            translationX: -16,
            at: firstTime,
            isPlaying: false,
            currentIndex: 50,
            wordCount: 100
        ))
        #expect(first.wordDelta == 2)
        #expect(first.effectivePointsPerWord == ReaderConfig.RSVP.basePointsPerWord)
        _ = session.endGesture()

        let second = try #require(session.updateGesture(
            translationX: -16,
            at: firstTime.addingTimeInterval(0.01),
            isPlaying: false,
            currentIndex: first.targetIndex,
            wordCount: 100
        ))

        #expect(second.wordDelta == 2)
        #expect(second.velocity == 0)
        #expect(second.effectivePointsPerWord == ReaderConfig.RSVP.basePointsPerWord)
    }

    @Test("B15: a quick swipe is scrub-only and never routed as a tap")
    func quickSwipeDoesNotTogglePlayback() {
        let session = RSVPPresentationSession()
        _ = session.updateGesture(
            translationX: -12,
            at: Date(timeIntervalSince1970: 2_000),
            isPlaying: false,
            currentIndex: 10,
            wordCount: 100
        )

        #expect(session.endGesture() == .scrubbed)
    }

    @Test func stationaryTouchRoutesToPlayPause() {
        let session = RSVPPresentationSession()
        _ = session.updateGesture(
            translationX: -2,
            at: Date(timeIntervalSince1970: 3_000),
            isPlaying: false,
            currentIndex: 10,
            wordCount: 100
        )

        #expect(session.endGesture() == .togglePlayback)
    }

    @Test func scrubDirectionAndBoundsUseWordCoordinates() throws {
        let forward = RSVPPresentationSession()
        let forwardUpdate = try #require(forward.updateGesture(
            translationX: -80,
            isPlaying: false,
            currentIndex: 95,
            wordCount: 100
        ))
        #expect(forwardUpdate.targetIndex == 99)
        #expect(forwardUpdate.wordDelta > 0)

        let backward = RSVPPresentationSession()
        let backwardUpdate = try #require(backward.updateGesture(
            translationX: 80,
            isPlaying: false,
            currentIndex: 3,
            wordCount: 100
        ))
        #expect(backwardUpdate.targetIndex == 0)
        #expect(backwardUpdate.wordDelta < 0)
    }

    @Test func subThresholdMovementDoesNotSeek() {
        let session = RSVPPresentationSession()
        let update = session.updateGesture(
            translationX: ReaderConfig.RSVP.scrubActivationDistance - 1,
            isPlaying: false,
            currentIndex: 5,
            wordCount: 10
        )

        #expect(update == nil)
        #expect(session.endGesture() == .togglePlayback)
    }

    @Test func playingAndEmptyStreamsCannotSeek() {
        let playing = RSVPPresentationSession()
        #expect(playing.updateGesture(
            translationX: -80,
            isPlaying: true,
            currentIndex: 5,
            wordCount: 10
        ) == nil)
        #expect(playing.endGesture() == .scrubbed)

        let empty = RSVPPresentationSession()
        #expect(empty.updateGesture(
            translationX: -80,
            isPlaying: false,
            currentIndex: 0,
            wordCount: 0
        ) == nil)
        #expect(empty.endGesture() == .scrubbed)
    }
}
