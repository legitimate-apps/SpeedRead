import CoreGraphics
import Foundation
import Observation

enum RSVPDisplayInteraction: Equatable {
    case togglePlayback
    case scrubbed
}

struct RSVPScrubUpdate: Equatable {
    let targetIndex: Int
    let wordDelta: Int
    let velocity: CGFloat
    let effectivePointsPerWord: CGFloat
    let shouldProduceHaptic: Bool
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

    private var lastDragX: CGFloat = 0
    private var dragAccumulator: CGFloat = 0
    private var lastDragTime: Date?
    private var dragVelocity: CGFloat = 0
    private var maximumTranslation: CGFloat = 0
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
    }

    func togglePlayback(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        if engine.state == .playing {
            engine.pause()
            return nil
        }
        guard engine.isLoaded else { return nil }
        let index = engine.currentIndex
        engine.play()
        positionCommitPolicy.pressedPlay(at: index, now: now)
        return ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now
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
        guard engine.state == .playing,
              positionCommitPolicy.shouldCommitAdvance(at: index, now: now) else {
            return nil
        }
        return ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now
        )
    }

    @discardableResult
    func recordBrowsePosition(
        _ index: Int,
        book: Book,
        saver: any ReadingPositionSaving
    ) -> Bool {
        book.ensurePositionMarkersInitialized()
        book.browseWordIndex = ReadingPositionCoordinator.clampedIndex(
            index,
            wordCount: cachedWords.count
        )
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
            now: now
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
            now: now
        )
        engine.stop()
        return commit
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

    func updateGesture(
        translationX: CGFloat,
        at now: Date = Date(),
        isPlaying: Bool,
        currentIndex: Int,
        wordCount: Int
    ) -> RSVPScrubUpdate? {
        maximumTranslation = max(maximumTranslation, abs(translationX))
        guard !isPlaying,
              wordCount > 0,
              maximumTranslation >= ReaderConfig.RSVP.scrubActivationDistance else {
            return nil
        }

        let deltaX = -(translationX - lastDragX)
        if let lastDragTime {
            let deltaTime = now.timeIntervalSince(lastDragTime)
            if deltaTime > 0 {
                dragVelocity = abs(deltaX / CGFloat(deltaTime))
            }
        }

        let velocityFactor = min(
            dragVelocity / ReaderConfig.RSVP.velocityPointsPerSecond,
            ReaderConfig.RSVP.maximumVelocityMultiplier / ReaderConfig.RSVP.basePointsPerWord
        )
        let effectivePointsPerWord = ReaderConfig.RSVP.basePointsPerWord / max(1, velocityFactor)

        dragAccumulator += deltaX
        let wordDelta = Int(dragAccumulator / effectivePointsPerWord)
        lastDragX = translationX
        lastDragTime = now

        guard wordDelta != 0 else { return nil }
        let target = min(max(0, currentIndex + wordDelta), wordCount - 1)
        dragAccumulator -= CGFloat(wordDelta) * effectivePointsPerWord
        return RSVPScrubUpdate(
            targetIndex: target,
            wordDelta: wordDelta,
            velocity: dragVelocity,
            effectivePointsPerWord: effectivePointsPerWord,
            shouldProduceHaptic: abs(wordDelta) >= ReaderConfig.RSVP.hapticWordInterval
                || target % ReaderConfig.RSVP.hapticWordInterval == 0
        )
    }

    func endGesture() -> RSVPDisplayInteraction {
        let interaction: RSVPDisplayInteraction = maximumTranslation >= ReaderConfig.RSVP.scrubActivationDistance
            ? .scrubbed
            : .togglePlayback
        lastDragX = 0
        dragAccumulator = 0
        lastDragTime = nil
        dragVelocity = 0
        maximumTranslation = 0
        return interaction
    }
}
