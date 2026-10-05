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

    /// A hundred five-letter words, 20 points a character: every pivot is 120 points from the next.
    private let track = RSVPScrubTrack(
        words: Array(repeating: "words", count: 100), advance: 20, availableWidth: 400)
    private let wordTravel: CGFloat = 120

    private func drag(
        _ session: RSVPPresentationSession,
        to translationX: CGFloat,
        at now: TimeInterval = 0,
        isPlaying: Bool = false,
        from currentIndex: Int,
        wordCount: Int = 100
    ) -> RSVPScrubUpdate? {
        session.updateGesture(
            translationX: translationX, at: now, isPlaying: isPlaying,
            currentIndex: currentIndex, wordCount: wordCount, track: track)
    }

    /// A drag that leaves at speed: the finger moves from rest to `translationX` in the 20 ms
    /// before `now`, so it lifts at `translationX / 0.02` points a second.
    private func flick(_ session: RSVPPresentationSession, to translationX: CGFloat, at now: TimeInterval, from index: Int) {
        _ = drag(session, to: 0, at: now - 0.02, from: index)
        _ = drag(session, to: translationX, at: now, from: index)
    }

    /// Runs the motion after release frame by frame, as the display link does, collecting updates.
    private func runUntilStill(_ session: RSVPPresentationSession, from start: TimeInterval) -> [RSVPScrubUpdate] {
        var updates: [RSVPScrubUpdate] = []
        var now = start
        while session.isAnimating, now < start + 5 {
            now += 1.0 / 60
            if let update = session.advance(at: now, track: track) { updates.append(update) }
        }
        return updates
    }

    @Test("B4: a new gesture starts from the finger, not from where the last one left the line")
    func newGestureStartsFromItsOwnTouch() throws {
        let session = RSVPPresentationSession()
        let first = try #require(drag(session, to: -250, from: 50))
        #expect(first.targetIndex == 52)
        _ = session.endGesture(at: 0, track: track)
        _ = runUntilStill(session, from: 0)
        #expect(session.scrub == nil)

        #expect(drag(session, to: -30, at: 10, from: first.targetIndex) == nil)
        let second = try #require(session.scrub)
        #expect(second.startIndex == 52)
        #expect(abs(second.offset - 30 / wordTravel) < 0.0001)
    }

    @Test("B15: a quick swipe is scrub-only and never routed as a tap")
    func quickSwipeDoesNotTogglePlayback() {
        let session = RSVPPresentationSession()
        _ = drag(session, to: -12, from: 10)
        #expect(session.endGesture(at: 0, track: track) == .scrubbed)
    }

    @Test func stationaryTouchRoutesToPlayPause() {
        let session = RSVPPresentationSession()
        _ = drag(session, to: -2, from: 10)
        #expect(session.endGesture(at: 0, track: track) == .togglePlayback)
        #expect(!session.isAnimating)
    }

    @Test func scrubDirectionAndBoundsUseWordCoordinates() throws {
        let forward = try #require(drag(RSVPPresentationSession(), to: -800, from: 95))
        #expect(forward.targetIndex == 99)
        #expect(forward.wordDelta == 4)

        let backward = try #require(drag(RSVPPresentationSession(), to: 800, from: 3))
        #expect(backward.targetIndex == 0)
        #expect(backward.wordDelta == -3)
    }

    @Test func subThresholdMovementDoesNotSeek() {
        let session = RSVPPresentationSession()
        #expect(drag(session, to: ReaderConfig.RSVP.scrubActivationDistance - 1, from: 5, wordCount: 10) == nil)
        #expect(session.scrub == nil)
        #expect(session.endGesture(at: 0, track: track) == .togglePlayback)
    }

    @Test func theLineMovesExactlyWithTheFinger() throws {
        // Mutations: a points-per-word constant instead of the track (the line outruns the finger),
        // or truncating instead of handing over at the halfway point.
        let session = RSVPPresentationSession()
        #expect(session.scrub == nil)

        // The strip appears as soon as the touch is a drag, before any word changes.
        #expect(drag(session, to: -8, from: 10) == nil)
        #expect(abs(try #require(session.scrub).offset - 8 / wordTravel) < 0.0001)

        // Just short of halfway: still word 10, the line dragged 59 points toward word 11.
        #expect(drag(session, to: -59, from: 10) == nil)
        #expect(abs(try #require(session.scrub).offset - 59 / wordTravel) < 0.0001)

        // Past halfway: word 11 is on the guides, 59 points short of them.
        let update = try #require(drag(session, to: -61, from: 10))
        #expect(update.targetIndex == 11)
        #expect(update.haptic == .word)
        let past = try #require(session.scrub)
        #expect(past.startIndex == 10)
        #expect(abs(past.offset - (-59 / wordTravel)) < 0.0001)

        // Three and a bit words in one move: one update, one tick.
        let jump = try #require(drag(session, to: -61 - 3 * wordTravel - 10, from: 11))
        #expect(jump.targetIndex == 14)
        #expect(jump.wordDelta == 3)
    }

    @Test func theLineStopsAtEitherEndOfTheBookWithOneKnockAndAVisibleStretch() throws {
        // Mutation: drop the edge latch, and every frame against the end knocks again.
        let atEnd = RSVPPresentationSession()
        let knock = try #require(drag(atEnd, to: -40, from: 99))
        #expect(knock.haptic == .edge)
        #expect(knock.wordDelta == 0)
        #expect(try #require(atEnd.scrub).offset == 0)
        // Past the last word the line gives toward the next word that is not there.
        #expect(try #require(atEnd.scrub).stretch == RSVPScrubStretch.displayed(40))
        #expect(drag(atEnd, to: -90, from: 99) == nil)
        #expect(try #require(atEnd.scrub).stretch == RSVPScrubStretch.displayed(90))
        // Easing off takes up the stretch first and does not knock again.
        #expect(drag(atEnd, to: -50, from: 99) == nil)
        #expect(try #require(atEnd.scrub).stretch == RSVPScrubStretch.displayed(50))
        // Coming fully back moves the line toward the previous word; returning knocks again.
        #expect(drag(atEnd, to: 30, from: 99) == nil)
        let away = try #require(atEnd.scrub)
        #expect(away.stretch == 0)
        #expect(abs(away.offset - (-30 / wordTravel)) < 0.0001)
        #expect(drag(atEnd, to: -140, from: 99)?.haptic == .edge)
        #expect(try #require(atEnd.scrub).stretch == RSVPScrubStretch.displayed(140))

        // At the first word, dragging right (back) gives the other way: the user sees the end.
        let atStart = RSVPPresentationSession()
        #expect(drag(atStart, to: 40, from: 0)?.haptic == .edge)
        let start = try #require(atStart.scrub)
        #expect(start.offset == 0)
        #expect(start.stretch == RSVPScrubStretch.displayed(-40))
        #expect(start.stretch < 0)
    }

    @Test func aStretchedLineSpringsBackOnceLetGo() throws {
        // Mutation: never relax the stretch, and the line stays pulled off its word.
        let session = RSVPPresentationSession()
        _ = drag(session, to: 120, from: 0)
        #expect(session.endGesture(at: 0, track: track) == .scrubbed)
        var last = abs(try #require(session.scrub).stretch)
        #expect(last > 0)
        var now: TimeInterval = 0
        while now < ReaderConfig.RSVP.settleDuration {
            now += 1.0 / 60
            #expect(session.advance(at: now, track: track) == nil)
            let given = abs(session.scrub?.stretch ?? 0)
            #expect(given <= last)
            last = given
        }
        #expect(session.scrub?.stretch == 0)
        _ = runUntilStill(session, from: now)
        #expect(session.scrub == nil)
        #expect(!session.isAnimating)
    }

    @Test func aTapOrADragWhilePlayingIsNotAScrub() {
        let tap = RSVPPresentationSession()
        _ = drag(tap, to: -2, from: 5, wordCount: 10)
        #expect(tap.scrub == nil)

        let playing = RSVPPresentationSession()
        _ = drag(playing, to: -80, isPlaying: true, from: 5, wordCount: 10)
        #expect(playing.scrub == nil)
    }

    @Test func playingAndEmptyStreamsCannotSeek() {
        let playing = RSVPPresentationSession()
        #expect(drag(playing, to: -300, isPlaying: true, from: 5, wordCount: 10) == nil)
        #expect(playing.endGesture(at: 0, track: track) == .scrubbed)
        #expect(!playing.isAnimating)

        let empty = RSVPPresentationSession()
        #expect(empty.updateGesture(
            translationX: -300, at: 0, isPlaying: false, currentIndex: 0, wordCount: 0,
            track: RSVPScrubTrack(words: [], advance: 20, availableWidth: 400)) == nil)
        #expect(empty.endGesture(at: 0, track: track) == .scrubbed)
        #expect(!empty.isAnimating)
    }

    @Test func aFlickGlidesOnTickingWordByWordThenLandsAndFades() throws {
        let session = RSVPPresentationSession()
        flick(session, to: -50, at: 1, from: 30)
        #expect(session.endGesture(at: 1, track: track) == .scrubbed)
        #expect(session.isAnimating)

        let updates = runUntilStill(session, from: 1)
        #expect(!session.isAnimating)
        #expect(session.scrub == nil)
        // 2,500 points a second for 0.25 s is 625 points from 50 in: nearest is six words on.
        let landed = try #require(updates.last).targetIndex
        #expect(landed == 36)
        #expect(updates.allSatisfy { $0.haptic == .word && $0.wordDelta > 0 })
        #expect(updates.map(\.wordDelta).reduce(0, +) == 6)
    }

    @Test func theStripFadesOutAfterLanding() throws {
        let session = RSVPPresentationSession()
        _ = drag(session, to: -20, from: 30)
        _ = session.endGesture(at: 0, track: track)
        // Settling back onto word 30 takes the settle duration; then the fade.
        _ = session.advance(at: ReaderConfig.RSVP.settleDuration, track: track)
        #expect(try #require(session.scrub).offset == 0)
        let fadeStart = ReaderConfig.RSVP.settleDuration
        _ = session.advance(at: fadeStart + ReaderConfig.RSVP.stripFadeDuration / 2, track: track)
        let halfway = try #require(session.scrub).opacity
        #expect(halfway > 0.4 && halfway < 0.6)
        _ = session.advance(at: fadeStart + ReaderConfig.RSVP.stripFadeDuration + 0.001, track: track)
        #expect(session.scrub == nil)
        #expect(!session.isAnimating)
    }

    @Test func aTouchDuringAGlideCatchesTheLineAndDoesNotPlay() throws {
        // Mutation: let the caught touch fall through as a tap, and stopping a glide starts reading.
        let session = RSVPPresentationSession()
        flick(session, to: -50, at: 0, from: 30)
        _ = session.endGesture(at: 0, track: track)
        let lastFrame = try #require(session.advance(at: 0.15, track: track)).targetIndex
        #expect(lastFrame == 33)

        // The line moved on between the last frame and the touch: the words it crossed are reported.
        // Mutation: count the catch's words from the caught position, and the reader misses them.
        let caught = try #require(drag(session, to: 0, at: 0.3, from: lastFrame))
        #expect(caught.targetIndex == 35)
        #expect(caught.wordDelta == 2)
        #expect(!session.isAnimating)
        #expect(session.endGesture(at: 0.31, track: track) == .scrubbed)
        // Settles onto the word it was caught on, never on past it.
        let rest = runUntilStill(session, from: 0.31)
        #expect(rest.allSatisfy { $0.targetIndex == 35 })
        #expect(session.scrub == nil)
    }

    @Test func aSuddenLastTouchEventCannotFlingASlowDrag() throws {
        // A slow drag (100 points a second, at 60 Hz) whose last event lands a millisecond after
        // the one before, 6 points on. Measured from those two alone that is 6,000 points a
        // second, a fling of tens of words: a reader rereading one word would be thrown off.
        // Mutation: measure from the last two events, and the line flies.
        let session = RSVPPresentationSession()
        var x: CGFloat = 0
        var now: TimeInterval = 0
        for _ in 0..<30 {
            now += 1.0 / 60
            x -= 100.0 / 60
            _ = drag(session, to: x, at: now, from: 30)
        }
        now += 0.001
        x -= 6
        let held = drag(session, to: x, at: now, from: 30)
        #expect(held == nil)
        #expect(session.endGesture(at: now, track: track) == .scrubbed)
        let updates = runUntilStill(session, from: now)
        // The finger left the line 56 points along: under half a word, so it settles back on 30.
        #expect(updates.isEmpty)
        #expect(session.scrub == nil)
    }

    @Test func aTapWhileTheStripFadesIsATap() {
        let session = RSVPPresentationSession()
        _ = drag(session, to: -20, from: 30)
        _ = session.endGesture(at: 0, track: track)
        _ = session.advance(at: ReaderConfig.RSVP.settleDuration, track: track)
        #expect(session.isAnimating)

        _ = drag(session, to: 0, at: ReaderConfig.RSVP.settleDuration + 0.01, from: 30)
        #expect(session.scrub == nil)
        #expect(session.endGesture(at: 1, track: track) == .togglePlayback)
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

    @Test(arguments: [false, true])
    func aDeviceThatYieldedCommitsNothingWhenItLeaves(byDisappearing: Bool) throws {
        // Mutation: drop the policy reset from the yield. Leaving then re-sends the watch's
        // word as this device's newer reading and rolls the still-playing watch back.
        let book = makeBook(text: "zero one two three four")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        _ = try #require(session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync))
        let yieldToWatch = try #require(sync.onYield)
        yieldToWatch(RemotePresence(bookId: book.id, wordIndex: 3, playStartedAt: .now, sentAt: .now))
        #expect(engine.state == .paused)
        #expect(engine.currentIndex == 3)

        let leaving = byDisappearing
            ? session.handleDisappear(engine: engine, book: book, saver: saver, sync: sync)
            : session.close(engine: engine, book: book, saver: saver, sync: sync)
        #expect(leaving == nil)
        #expect(sync.indices == [0], "Only the play's own commit")
    }

    @Test func readingHereAgainAfterAYieldCommitsOnLeaving() throws {
        // The control for the test above: the reset must not outlive the next play.
        let book = makeBook(text: "zero one two three four")
        let engine = RSVPEngine()
        let session = RSVPPresentationSession()
        let saver = RSVPSaver()
        let sync = RSVPSync()
        session.load(book: book, engine: engine, wpm: 300)
        _ = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)
        let yieldToWatch = try #require(sync.onYield)
        yieldToWatch(RemotePresence(bookId: book.id, wordIndex: 3, playStartedAt: .now, sentAt: .now))
        _ = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)
        let leaving = try #require(session.close(engine: engine, book: book, saver: saver, sync: sync))
        #expect(leaving.index == 3)
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
    private(set) var onYield: ((RemotePresence) -> Void)?

    func beginLocalRun(
        bookId: UUID,
        snapshot: @escaping () -> WatchSyncLogic.PositionPayload?,
        onYield: @escaping (RemotePresence) -> Void
    ) {
        self.onYield = onYield
    }

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
