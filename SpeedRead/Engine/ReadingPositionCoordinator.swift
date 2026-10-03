import Foundation

enum ReadingPositionCoordinator {
    /// Completion belongs to this commit, not the furthest-read high-water mark.
    /// Keep the receiving device's original date; use the sender's date only if absent.
    nonisolated static func completionDate(
        didFinish: Bool,
        index: Int,
        wordCount: Int,
        existingDate: Date?,
        incomingDate: Date? = nil,
        now: Date
    ) -> Date? {
        guard didFinish, wordCount > 0, index == wordCount - 1 else { return nil }
        return existingDate ?? incomingDate ?? now
    }

    nonisolated static func clampedIndex(_ index: Int, wordCount: Int) -> Int {
        // Clamp both sides: a caller inside WatchSyncService may construct a payload
        // directly and need not be downstream of PositionPayload.decode's lower-bound check.
        guard wordCount > 0 else { return 0 }
        return min(max(0, index), wordCount - 1)
    }
}
