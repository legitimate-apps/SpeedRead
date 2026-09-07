enum ReadingPositionCoordinator {
    static func clampedIndex(_ index: Int, wordCount: Int) -> Int {
        // Clamp both sides: a caller inside WatchSyncService may construct a payload
        // directly and need not be downstream of PositionPayload.decode's lower-bound check.
        guard wordCount > 0 else { return 0 }
        return min(max(0, index), wordCount - 1)
    }
}
