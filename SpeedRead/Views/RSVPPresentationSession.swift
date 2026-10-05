import CoreGraphics
import Foundation
import Observation
import SwiftData

enum RSVPDisplayInteraction: Equatable {
    case togglePlayback
    case scrubbed
}

/// A drag through the book, from the moment it moves far enough to be one until the line of
/// words has landed and faded.
struct RSVPScrubState: Equatable {
    /// The word the drag started on.
    let startIndex: Int
    /// How far the line of words is dragged past the current word, in words: positive is
    /// toward the next word. The current word is always the nearest, so this stays within a half.
    var offset: CGFloat
    /// 1 while the line is held or moving; falls to 0 as it fades out after landing.
    var opacity: Double = 1
    /// Points the line has given past an end of the book, toward the next word when positive.
    var stretch: CGFloat = 0
}

enum RSVPScrubHaptic: Equatable {
    /// The guides passed to another word.
    case word
    /// The line ran into the start or end of the book.
    case edge
}

struct RSVPScrubUpdate: Equatable {
    let targetIndex: Int
    let wordDelta: Int
    let haptic: RSVPScrubHaptic?
}

enum RSVPFeedbackKind: Equatable {
    case bookmark
    case highlight
}

struct RSVPFeedbackFlash: Equatable, Identifiable {
    let id: Int
    let kind: RSVPFeedbackKind
}

struct RSVPBookmarkDraft: Equatable {
    let wordIndex: Int
    let previewText: String
}

struct RSVPHighlightDraft: Equatable {
    let startIndex: Int
    let endIndex: Int
    let text: String
}

@Observable
@MainActor
final class RSVPPresentationSession {
    private(set) var cachedWords: [String] = []
    private(set) var highlightStartIndex: Int?
    private(set) var feedbackFlash: RSVPFeedbackFlash?
    private(set) var scrub: RSVPScrubState?

    private var lastDragX: CGFloat = 0
    private var maximumTranslation: CGFloat = 0
    private var line: RSVPScrubPosition?
    private var glide: RSVPScrubGlide?
    private var fadeStart: TimeInterval?
    /// The touch stopped a glide, so lifting it settles the line instead of toggling playback.
    private var caughtGlide = false
    /// Points the finger has pulled the line past an end of the book.
    private var stretch: CGFloat = 0
    /// When the finger let go of a stretched line, and how far it was pulled then.
    private var stretchRelease: (start: TimeInterval, points: CGFloat)?
    private var releaseVelocity = RSVPReleaseVelocity()
    private var nextFeedbackID = 0
    private var didCommitClose = false
    private var positionCommitPolicy = PlaybackPositionCommitPolicy()

    func load(book: Book, engine: RSVPEngine, wpm: Int) {
        book.ensureTokensCached()
        book.ensurePositionMarkersInitialized()
        cachedWords = book.words
        didCommitClose = false
        positionCommitPolicy.reset()
        engine.wpm = wpm
        engine.load(words: cachedWords, startingAt: book.browseWordIndex)
        engine.annotate(text: book.extractedText)
    }

    func togglePlayback(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        let positionSync = sync ?? WatchSyncService.shared
        if engine.state == .playing {
            // Pausing is the handoff moment: the word you stopped on becomes the place everywhere.
            let index = engine.snapshotIndexAndPause()
            positionSync.endLocalRun(bookId: book.id)
            return ReadingPositionCoordinator.commit(
                index,
                wordCount: cachedWords.count,
                book: book,
                saver: saver,
                sync: positionSync,
                now: now,
                didFinish: engine.didFinish
            )
        }
        guard engine.isLoaded else { return nil }
        let index = engine.currentIndex
        engine.play()
        positionCommitPolicy.pressedPlay(at: index, now: now)
        positionSync.beginLocalRun(
            bookId: book.id,
            snapshot: { [weak engine] in
                guard let engine else { return nil }
                return book.positionPayload().movingPlace(to: engine.currentIndex, at: Date())
            },
            onYield: { [weak self, weak engine] presence in
                // The other device took the book: stop without committing, and show its word.
                // Nothing played here is left to commit, so leaving must not send its word back.
                self?.positionCommitPolicy.reset()
                engine?.pause()
                engine?.seek(to: presence.wordIndex)
            }
        )
        return ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now,
            didFinish: engine.didFinish
        )
    }

    func commitPlaybackAdvanceIfNeeded(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        let index = engine.currentIndex
        guard positionCommitPolicy.hasPlayed,
              engine.didFinish || (engine.state == .playing
                && positionCommitPolicy.shouldCommitAdvance(at: index, now: now)) else {
            return nil
        }
        if engine.didFinish { (sync ?? WatchSyncService.shared).endLocalRun(bookId: book.id) }
        return ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now,
            didFinish: engine.didFinish
        )
    }

    /// A scrub, chapter or bookmark move. Following the watch to a word already stored as the
    /// place is not a move, so it sends nothing back.
    @discardableResult
    func recordBrowsePosition(
        _ index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> Bool {
        book.ensurePositionMarkersInitialized()
        let target = ReadingPositionCoordinator.clampedIndex(index, wordCount: cachedWords.count)
        guard target != book.browseWordIndex else { return true }
        book.browseWordIndex = target
        book.browseDate = now
        (sync ?? WatchSyncService.shared).publishPlace(book.positionPayload())
        do {
            try saver.save()
            return true
        } catch {
            return false
        }
    }

    func close(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        let index = engine.snapshotIndexAndPause()
        (sync ?? WatchSyncService.shared).endLocalRun(bookId: book.id)
        guard positionCommitPolicy.hasPlayed else {
            didCommitClose = true
            return nil
        }
        let commit = ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now,
            didFinish: engine.didFinish
        )
        didCommitClose = true
        return commit
    }

    func handleDisappear(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        guard !didCommitClose else {
            engine.stop()
            return nil
        }
        guard engine.isLoaded else {
            engine.stop()
            return nil
        }
        let index = engine.snapshotIndexAndPause()
        (sync ?? WatchSyncService.shared).endLocalRun(bookId: book.id)
        guard positionCommitPolicy.hasPlayed else {
            engine.stop()
            return nil
        }
        let commit = ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now,
            didFinish: engine.didFinish
        )
        engine.stop()
        return commit
    }

    func addBookmark(at index: Int, book: Book, modelContext: ModelContext,
                     annotationSync: any AnnotationChangeNoting = ServerAnnotationSync.shared) {
        let draft = bookmarkDraft(at: index)
        let bookmark = Bookmark(wordIndex: draft.wordIndex, previewText: draft.previewText)
        bookmark.book = book
        modelContext.insert(bookmark)
        annotationSync.noteChanged(bookId: book.id)
    }

    /// Returns whether the second tap completed and inserted a highlight.
    func toggleHighlight(at index: Int, book: Book, modelContext: ModelContext,
                         annotationSync: any AnnotationChangeNoting = ServerAnnotationSync.shared) -> Bool {
        guard let draft = toggleHighlight(at: index) else { return false }
        let highlight = Highlight(
            startWordIndex: draft.startIndex,
            endWordIndex: draft.endIndex,
            highlightedText: draft.text
        )
        highlight.book = book
        modelContext.insert(highlight)
        annotationSync.noteChanged(bookId: book.id)
        return true
    }

    func bookmarkDraft(at index: Int) -> RSVPBookmarkDraft {
        let clamped = ReadingPositionCoordinator.clampedIndex(index, wordCount: cachedWords.count)
        return RSVPBookmarkDraft(
            wordIndex: clamped,
            previewText: Bookmark.previewText(from: cachedWords, at: clamped)
        )
    }

    func toggleHighlight(at index: Int) -> RSVPHighlightDraft? {
        guard !cachedWords.isEmpty else { return nil }
        let clamped = ReadingPositionCoordinator.clampedIndex(index, wordCount: cachedWords.count)
        guard let startIndex = highlightStartIndex else {
            highlightStartIndex = clamped
            return nil
        }

        let actualStart = min(startIndex, clamped)
        let actualEnd = max(startIndex, clamped)
        highlightStartIndex = nil
        return RSVPHighlightDraft(
            startIndex: actualStart,
            endIndex: actualEnd,
            text: Highlight.captureText(from: cachedWords, start: actualStart, end: actualEnd)
        )
    }

    func requestFeedback(_ kind: RSVPFeedbackKind) -> RSVPFeedbackFlash {
        nextFeedbackID += 1
        let flash = RSVPFeedbackFlash(id: nextFeedbackID, kind: kind)
        feedbackFlash = flash
        return flash
    }

    func clearFeedback(_ flash: RSVPFeedbackFlash) {
        guard feedbackFlash == flash else { return }
        feedbackFlash = nil
    }

    /// The line of words is still moving or fading after the finger lifted: call `advance` each frame.
    var isAnimating: Bool { glide != nil || fadeStart != nil || stretchRelease != nil }

    /// A touch on the word. The line follows the finger exactly once the touch has moved far enough
    /// to be a drag; a touch during a glide stops the line where it is, like a scroll view.
    func updateGesture(
        translationX: CGFloat,
        at now: TimeInterval,
        isPlaying: Bool,
        currentIndex: Int,
        wordCount: Int,
        track: RSVPScrubTrack
    ) -> RSVPScrubUpdate? {
        if fadeStart != nil {
            fadeStart = nil
            line = nil
            scrub = nil
        }
        stretchRelease = nil
        releaseVelocity.record(translationX, at: now)
        // The word last reported, so a word reached between frames is not lost to the catch.
        let before = line?.index ?? currentIndex
        if let moving = glide {
            line = moving.position(at: now, on: track)
            glide = nil
            caughtGlide = true
        }
        maximumTranslation = max(maximumTranslation, abs(translationX))
        guard !isPlaying,
              wordCount > 0,
              caughtGlide || maximumTranslation >= ReaderConfig.RSVP.scrubActivationDistance else {
            return nil
        }

        var position = line ?? RSVPScrubPosition(index: currentIndex)
        var points = -(translationX - lastDragX)
        lastDragX = translationX
        let wasStretched = stretch != 0
        // Coming back from past an end takes up the stretch before the line moves.
        if wasStretched, (points > 0) != (stretch > 0) {
            let taken = min(abs(points), abs(stretch))
            stretch += stretch > 0 ? -taken : taken
            points += points > 0 ? -taken : taken
        }
        stretch += position.move(by: points, on: track)
        line = position
        scrub = RSVPScrubState(
            startIndex: scrub?.startIndex ?? before,
            offset: position.offset(on: track),
            stretch: RSVPScrubStretch.displayed(stretch)
        )

        let hitEdge = stretch != 0 && !wasStretched
        let wordDelta = position.index - before
        guard wordDelta != 0 || hitEdge else { return nil }
        return RSVPScrubUpdate(
            targetIndex: position.index,
            wordDelta: wordDelta,
            haptic: hitEdge ? .edge : .word
        )
    }

    /// The finger lifted. A drag carries on as a glide at the speed the finger left at; a touch
    /// that never moved toggles playback.
    func endGesture(at now: TimeInterval, track: RSVPScrubTrack) -> RSVPDisplayInteraction {
        let interaction: RSVPDisplayInteraction =
            caughtGlide || maximumTranslation >= ReaderConfig.RSVP.scrubActivationDistance
            ? .scrubbed
            : .togglePlayback
        if let position = line {
            // The finger moving left moves the line toward the next word.
            glide = RSVPScrubGlide(from: position, velocity: -releaseVelocity.velocity(at: now), at: now, on: track)
        }
        if stretch != 0 {
            stretchRelease = (now, stretch)
            stretch = 0
        }
        lastDragX = 0
        maximumTranslation = 0
        caughtGlide = false
        releaseVelocity = RSVPReleaseVelocity()
        return interaction
    }

    /// One frame of the line's motion after the finger lifted.
    func advance(at now: TimeInterval, track: RSVPScrubTrack) -> RSVPScrubUpdate? {
        if let release = stretchRelease {
            // A line pulled past an end springs back onto it.
            let t = min(1, (now - release.start) / ReaderConfig.RSVP.settleDuration)
            scrub?.stretch = RSVPScrubStretch.displayed(release.points * CGFloat(pow(1 - t, 3)))
            if t >= 1 { stretchRelease = nil }
        }
        if let moving = glide {
            let before = line?.index ?? moving.origin.index
            let position = moving.position(at: now, on: track)
            line = position
            scrub = RSVPScrubState(
                startIndex: scrub?.startIndex ?? moving.origin.index,
                offset: position.offset(on: track),
                stretch: scrub?.stretch ?? 0
            )
            if moving.isFinished(at: now) {
                glide = nil
                fadeStart = now
            }
            let wordDelta = position.index - before
            return wordDelta == 0 ? nil : RSVPScrubUpdate(targetIndex: position.index, wordDelta: wordDelta, haptic: .word)
        }
        if let fadeStart {
            let faded = (now - fadeStart) / ReaderConfig.RSVP.stripFadeDuration
            if faded >= 1 {
                self.fadeStart = nil
                line = nil
                scrub = nil
            } else {
                scrub?.opacity = 1 - faded
            }
        }
        return nil
    }
}
