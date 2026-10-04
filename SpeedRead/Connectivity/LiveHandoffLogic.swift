import Foundation

/// Which side of the phone↔watch pair is speaking.
nonisolated enum HandoffDevice: Sendable {
    case phone
    case watch

    static var current: HandoffDevice {
        #if os(watchOS)
        .watch
        #else
        .phone
        #endif
    }

    /// The other side of the pair: the one a remote presence comes from.
    var counterpart: HandoffDevice { self == .phone ? .watch : .phone }

    var displayName: String { self == .phone ? "iPhone" : "Apple Watch" }
}

/// The other device is reading a book right now.
nonisolated struct RemotePresence: Equatable, Sendable {
    let bookId: UUID
    /// The last word heard from it: where a takeover starts.
    let wordIndex: Int
    /// When its reading run began. Orders takeovers.
    let playStartedAt: Date
    /// When the payload left it. Decides liveness.
    let sentAt: Date
}

/// Decisions for keeping the phone and watch on one place, and for which of them owns a book
/// while it is being read. See docs/superpowers/specs/2026-10-04-live-handoff-design.md.
nonisolated enum LiveHandoffLogic {
    /// How often a reading device repeats its place.
    static let heartbeatInterval: Duration = .seconds(1)
    /// How long a heartbeat keeps the other device's card up.
    static let livenessWindow: TimeInterval = 6
    /// Crown and scrub moves are coalesced to the latest within this interval.
    static let placeCoalescing: Duration = .milliseconds(250)
    /// While live, place updates are persisted at most this often (the watch store holds every
    /// book's text, so it is not rewritten per heartbeat).
    static let livePersistInterval: TimeInterval = 5

    /// The place is last-write-wins on the time of the move, in either direction.
    static func shouldApplyPlace(localDate: Date?, incomingDate: Date) -> Bool {
        guard let localDate else { return true }
        return incomingDate > localDate
    }

    /// Reads the sender's clock, so a late-delivered context cannot look current.
    static func isLive(sentAt: Date, now: Date) -> Bool {
        abs(now.timeIntervalSince(sentAt)) < livenessWindow
    }

    static func presence(
        from payload: WatchSyncLogic.PositionPayload,
        now: Date
    ) -> RemotePresence? {
        guard payload.isPlaying,
              let playStartedAt = payload.playStartedAt,
              isLive(sentAt: payload.sentAt, now: now) else { return nil }
        return RemotePresence(
            bookId: payload.bookId,
            wordIndex: payload.browseWordIndex,
            playStartedAt: playStartedAt,
            sentAt: payload.sentAt
        )
    }

    static func expiry(of presence: RemotePresence) -> Date {
        presence.sentAt.addingTimeInterval(livenessWindow)
    }

    // MARK: Card text

    static func cardTitle(readingOn device: HandoffDevice) -> String {
        "Reading on \(device.displayName)"
    }

    /// "Chapter 3 · 34%", or just the percentage when the book has no chapters.
    static func cardDetail(presence: RemotePresence, wordCount: Int, chapters: [ChapterMark]) -> String {
        let index = ReadingPositionCoordinator.clampedIndex(presence.wordIndex, wordCount: wordCount)
        let percent = wordCount > 0 ? Int((Double(index) / Double(wordCount) * 100).rounded(.down)) : 0
        let chapter = chapters.last { $0.startWordIndex <= index }?.title
        return [chapter, "\(percent)%"].compactMap { $0 }.joined(separator: " · ")
    }

    /// The later reading run owns the book. Ties go to the phone.
    static func shouldYield(
        localRunStartedAt: Date,
        incoming: RemotePresence,
        localDevice: HandoffDevice
    ) -> Bool {
        if incoming.playStartedAt != localRunStartedAt {
            return incoming.playStartedAt > localRunStartedAt
        }
        return localDevice == .watch
    }
}
