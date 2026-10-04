import Foundation
import Testing
@testable import SpeedRead

@Suite("RSVP presentation session")
@MainActor
struct RSVPPresentationSessionTests {
    @Test func loadsPersistedTokensAtTheSavedPositionAndSpeed() {
        let book = makeBook(text: "zero one two")
        book.lastReadWordIndex = 2
        book.browseWordIndex = 2
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()

        session.load(book: book, engine: engine, wpm: 475)

        #expect(session.cachedWords == ["zero", "one", "two"])
        #expect(engine.totalWords == 3)
        #expect(engine.currentIndex == 2)
        #expect(engine.currentWord == "two")
        #expect(engine.wpm == 475)
    }

    @Test func emptyStreamLoadsWithoutAnInvalidIndex() {
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()

        session.load(book: makeBook(text: ""), engine: engine, wpm: 300)

        #expect(session.cachedWords.isEmpty)
        #expect(engine.totalWords == 0)
        #expect(engine.currentIndex == 0)
        #expect(engine.currentWord.isEmpty)
    }

    @Test func pressingPlayCommitsTheVisiblePositionAndHighWaterMark() throws {
        let book = makeBook(text: "zero one two three")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        let now = Date(timeIntervalSince1970: 100)
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)

        let commit = try #require(session.togglePlayback(
            engine: engine, book: book, saver: saver, sync: sync, now: now
        ))

        #expect(commit.index == 2)
        #expect(book.lastReadWordIndex == 2)
        #expect(book.furthestReadWordIndex == 2)
        #expect(engine.state == .playing)
        #expect(saver.saveCount == 1)
        #expect(sync.indices == [2])
    }

    @Test func playbackAdvancementIsThrottledThenCommits() throws {
        let book = makeBook(text: "zero one two three four")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        let start = Date(timeIntervalSince1970: 1_000)
        session.load(book: book, engine: engine, wpm: 300)
        _ = session.togglePlayback(
            engine: engine, book: book, saver: saver, sync: sync, now: start
        )
        engine.seek(to: 1)

        let early = session.commitPlaybackAdvanceIfNeeded(
            engine: engine, book: book, saver: saver, sync: sync,
            now: start.addingTimeInterval(4.9)
        )
        let due = try #require(session.commitPlaybackAdvanceIfNeeded(
            engine: engine, book: book, saver: saver, sync: sync,
            now: start.addingTimeInterval(5)
        ))

        #expect(early == nil)
        #expect(due.index == 1)
        #expect(saver.saveCount == 2)
        #expect(sync.indices == [0, 1])
    }

    @Test func scrubUpdatesOnlyTheLocalBrowseMarker() {
        let book = makeBook(text: "zero one two three")
        book.lastReadWordIndex = 1
        book.lastReadDate = Date(timeIntervalSince1970: 50)
        book.furthestReadWordIndex = 2
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        session.load(book: book, engine: RSVPEngine(), wpm: 300)

        let didSave = session.recordBrowsePosition(3, book: book, saver: saver)

        #expect(didSave)
        #expect(book.browseWordIndex == 3)
        #expect(book.lastReadWordIndex == 1)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 50))
        #expect(book.furthestReadWordIndex == 2)
        #expect(saver.saveCount == 1)
    }

    @Test func closingWithoutEverPlayingDoesNotCommitBrowsing() {
        let book = makeBook(text: "zero one two")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)

        let commit = session.close(engine: engine, book: book, saver: saver, sync: sync)

        #expect(commit == nil)
        #expect(book.lastReadWordIndex == 0)
        #expect(book.furthestReadWordIndex == 0)
        #expect(sync.indices.isEmpty)
    }

    @Test func closeSnapshotsBeforePauseAndPersistsTheVisibleIndex() {
        let book = makeBook(text: "zero one two three")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        let now = Date(timeIntervalSince1970: 4_000)
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)
        _ = session.togglePlayback(
            engine: engine,
            book: book,
            saver: saver,
            sync: sync,
            now: now.addingTimeInterval(-1)
        )

        let commit = session.close(
            engine: engine,
            book: book,
            saver: saver,
            sync: sync,
            now: now
        )

        #expect(commit == ReadingPositionCommit(index: 2, timestamp: now, didSave: true))
        #expect(engine.state == .paused)
        #expect(engine.currentIndex == 2)
        #expect(book.lastReadWordIndex == 2)
        #expect(saver.saveCount == 2)
        #expect(sync.indices == [2, 2])
    }

    @Test func disappearCommitsLoadedPositionBeforeStopping() throws {
        let book = makeBook(text: "zero one two")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)
        _ = session.togglePlayback(
            engine: engine,
            book: book,
            saver: saver,
            sync: sync,
            now: Date(timeIntervalSince1970: 100)
        )

        let commit = try #require(session.handleDisappear(
            engine: engine,
            book: book,
            saver: saver,
            sync: sync
        ))

        #expect(commit.index == 2)
        #expect(book.lastReadWordIndex == 2)
        #expect(sync.indices == [2, 2])
        #expect(engine.state == .idle)
        #expect(engine.currentIndex == 0)
        #expect(engine.totalWords == 0)
    }

    @Test func closeIsNotPersistedAgainWhenDisappearFollows() {
        let book = makeBook(text: "zero one two")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)
        _ = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)

        _ = session.close(engine: engine, book: book, saver: saver, sync: sync)
        let duplicate = session.handleDisappear(engine: engine, book: book, saver: saver, sync: sync)

        #expect(duplicate == nil)
        #expect(saver.saveCount == 2)
        #expect(sync.indices == [2, 2])
        #expect(engine.state == .idle)
    }

    @Test func disappearDoesNotPersistAnUnloadedEngine() {
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        let saver = RSVPSaver()
        let sync = RSVPSync()

        let commit = session.handleDisappear(
            engine: engine,
            book: makeBook(text: "zero"),
            saver: saver,
            sync: sync
        )

        #expect(commit == nil)
        #expect(saver.saveCount == 0)
        #expect(sync.indices.isEmpty)
    }

    @Test func bookmarkDraftClampsAndUsesTheVisibleWordWindow() {
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        session.load(book: makeBook(text: "zero one two three four"), engine: engine, wpm: 300)

        #expect(session.bookmarkDraft(at: 99) == .init(
            wordIndex: 4,
            previewText: "two three four"
        ))
    }

    @Test func highlightCanBeCompletedInEitherDirection() {
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        session.load(book: makeBook(text: "zero one two three"), engine: engine, wpm: 300)

        #expect(session.toggleHighlight(at: 3) == nil)
        #expect(session.highlightStartIndex == 3)
        #expect(session.toggleHighlight(at: 1) == .init(startIndex: 1, endIndex: 3, text: "one two three"))
        #expect(session.highlightStartIndex == nil)
    }

    @Test func feedbackTokensAreUniqueAndOldTasksCannotClearNewFeedback() {
        let session = RSVPPresentationSession()
        let old = session.requestFeedback(.bookmark)
        let new = session.requestFeedback(.highlight)

        #expect(old.id != new.id)
        #expect(session.feedbackFlash == new)
        session.clearFeedback(old)
        #expect(session.feedbackFlash == new)
        session.clearFeedback(new)
        #expect(session.feedbackFlash == nil)
    }

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

    @Test func zeroElapsedTimeKeepsBaseScrubResolution() throws {
        let session = RSVPPresentationSession()
        let now = Date(timeIntervalSince1970: 5_000)
        _ = try #require(session.updateGesture(
            translationX: -8,
            at: now,
            isPlaying: false,
            currentIndex: 10,
            wordCount: 100
        ))

        let update = try #require(session.updateGesture(
            translationX: -16,
            at: now,
            isPlaying: false,
            currentIndex: 11,
            wordCount: 100
        ))

        #expect(update.velocity == 0)
        #expect(update.effectivePointsPerWord == ReaderConfig.RSVP.basePointsPerWord)
        #expect(update.wordDelta == 1)
    }

    @Test func withinGestureVelocityAcceleratesAndCapsScrubResolution() throws {
        let session = RSVPPresentationSession()
        let start = Date(timeIntervalSince1970: 6_000)
        _ = try #require(session.updateGesture(
            translationX: -8,
            at: start,
            isPlaying: false,
            currentIndex: 10,
            wordCount: 1_000
        ))

        let accelerated = try #require(session.updateGesture(
            translationX: -24,
            at: start.addingTimeInterval(0.01),
            isPlaying: false,
            currentIndex: 11,
            wordCount: 1_000
        ))
        #expect(accelerated.velocity > ReaderConfig.RSVP.velocityPointsPerSecond)
        #expect(accelerated.effectivePointsPerWord < ReaderConfig.RSVP.basePointsPerWord)

        let capped = try #require(session.updateGesture(
            translationX: -124,
            at: start.addingTimeInterval(0.011),
            isPlaying: false,
            currentIndex: accelerated.targetIndex,
            wordCount: 1_000
        ))
        let minimumPointsPerWord = ReaderConfig.RSVP.basePointsPerWord
            / (ReaderConfig.RSVP.maximumVelocityMultiplier / ReaderConfig.RSVP.basePointsPerWord)
        #expect(abs(capped.effectivePointsPerWord - minimumPointsPerWord) < 0.0001)
        #expect(capped.wordDelta > accelerated.wordDelta)
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

    @Test func pauseCommitsTheVisibleIndexWhichReleasesTheOtherDevice() throws {
        // Mutations: remove engine.pause(), replace it with stop(), or skip the pause commit
        // (that commit is the paused payload that takes the other device's card down).
        let book = makeBook(text: "zero one two")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        engine.seek(to: 2)
        _ = try #require(session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync))
        let result = try #require(session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync))
        #expect(result.index == 2)
        #expect(engine.state == .paused)
        #expect(engine.currentIndex == 2)
        #expect(saver.saveCount == 2)
        #expect(sync.indices == [2, 2])
    }

    @Test func unloadedPlaybackDoesNotCommit() {
        // Mutation: remove the isLoaded guard; an unloaded stream then overwrites the book's position.
        let book = makeBook(text: "zero one two")
        book.lastReadWordIndex = 2
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        let result = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)
        #expect(result == nil)
        #expect(book.lastReadWordIndex == 2)
        #expect(engine.state == .idle)
        #expect(saver.saveCount == 0)
        #expect(sync.indices.isEmpty)
    }

    private func makeBook(text: String) -> Book {
        Book(title: "Test", author: "Author", extractedText: text, sourceFileName: "test.txt")
    }
}

@MainActor
private final class RSVPSaver: ReadingPositionSaving {
    private(set) var saveCount = 0

    func save() throws {
        saveCount += 1
    }
}

@MainActor
private final class RSVPSync: ReadingPositionSyncing {
    private(set) var indices: [Int] = []

    func syncReadingPosition(
        bookId: UUID,
        bookTitle: String,
        wordIndex: Int,
        timestamp: Date,
        furthestReadWordIndex: Int,
        didFinish: Bool,
        finishedAt: Date?
    ) {
        indices.append(wordIndex)
    }
}
