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

    func load(book: Book, engine: RSVPEngine, wpm: Int) {
        // Deliberately inert TDD scaffold. The behavior lands after its tests.
    }

    func close(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit {
        engine.stop()
        return ReadingPositionCommit(index: 0, timestamp: now, didSave: false)
    }

    func handleDisappear(
        engine: RSVPEngine,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit? {
        engine.stop()
        return nil
    }

    func bookmarkDraft(at index: Int) -> RSVPBookmarkDraft {
        RSVPBookmarkDraft(wordIndex: 0, previewText: "")
    }

    func toggleHighlight(at index: Int) -> RSVPHighlightDraft? {
        nil
    }

    func requestFeedback(_ kind: RSVPFeedbackKind) -> RSVPFeedbackFlash {
        RSVPFeedbackFlash(id: 0, kind: kind)
    }

    func clearFeedback(_ flash: RSVPFeedbackFlash) {}

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
