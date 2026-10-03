import Foundation

/// Decisions for syncing a book's reading position with a library server. Pure: every input is
/// a value, so each rule is testable without a server, a model context or a clock.
nonisolated enum ServerPositionLogic {
    /// The server marks a book finished at this percentage (CWNG), so an unfinished position is
    /// never pushed at or above it — otherwise reading the last page would finish the book on
    /// every other reader.
    static let finishedThreshold = 0.99
    static let highestUnfinishedPercentage = 0.989

    /// The keys a server may know this book by, best first. Only the server the book was
    /// downloaded from: its download registered the digest, and the book id is its own. A book
    /// that was not downloaded from this server has no key it is guaranteed to share.
    static func documentKeys(digest: String?, origin: BookOrigin?, serverID: UUID) -> [String] {
        guard let origin, origin.serverID == serverID else { return [] }
        return [digest, origin.serverBookID].compactMap { $0 }
    }

    static func pushPercentage(index: Int, wordCount: Int, finished: Bool) -> Double {
        if finished { return 1 }
        guard wordCount > 0 else { return 0 }
        let fraction = Double(ReadingPositionCoordinator.clampedIndex(index, wordCount: wordCount)) / Double(wordCount)
        return min(fraction, highestUnfinishedPercentage)
    }

    /// A remote position as a place in this copy of the book: the anchor when it can be placed
    /// with confidence, otherwise the percentage.
    struct Placement: Equatable, Sendable {
        let index: Int
        let finished: Bool
        let anchored: Bool
    }

    static func place(_ remote: KOSyncRemotePosition, in text: AnchoredText) -> Placement? {
        let wordCount = text.tokenCount
        guard wordCount > 0 else { return nil }
        if remote.percentage >= finishedThreshold {
            return Placement(index: wordCount - 1, finished: true, anchored: false)
        }
        if let anchor = remote.anchor, let index = text.resolve(anchor, near: remote.percentage) {
            return Placement(index: index, finished: false, anchored: true)
        }
        let index = ReadingPositionCoordinator.clampedIndex(Int(remote.percentage * Double(wordCount)), wordCount: wordCount)
        return Placement(index: index, finished: false, anchored: false)
    }

    struct Local: Equatable, Sendable {
        let index: Int
        let wordCount: Int
        let lastReadDate: Date?
        let finished: Bool
    }

    /// Offer a remote position only when another reader set it after this device last read, it
    /// has not been declined already, and it is somewhere else. Never a silent jump (CORPUS §4.4).
    static func shouldOffer(
        _ remote: KOSyncRemotePosition,
        placement: Placement,
        local: Local,
        deviceID: String,
        declinedTimestamp: Date?
    ) -> Bool {
        guard remote.deviceID != deviceID, let timestamp = remote.timestamp else { return false }
        if let lastReadDate = local.lastReadDate, timestamp <= lastReadDate { return false }
        if let declinedTimestamp, timestamp <= declinedTimestamp { return false }
        let materialDifference = max(5, Int(ceil(Double(local.wordCount) * 0.01)))
        return placement.finished != local.finished
            || abs(placement.index - local.index) >= materialDifference
    }
}
