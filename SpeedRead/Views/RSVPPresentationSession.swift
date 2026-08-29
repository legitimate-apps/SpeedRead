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

@Observable
@MainActor
final class RSVPPresentationSession {
    private var lastDragX: CGFloat = 0
    private var dragAccumulator: CGFloat = 0
    private var lastDragTime: Date?
    private var dragVelocity: CGFloat = 0
    private var maximumTranslation: CGFloat = 0
    private var didScrub = false

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

        didScrub = true
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
        lastDragX = 0
        dragAccumulator = 0
        dragVelocity = 0
        maximumTranslation = 0
        didScrub = false
        // Preserves both reported gesture defects until the red tests exist.
        // `lastDragTime` remains stale and the independent tap always toggles.
        return .togglePlayback
    }
}
