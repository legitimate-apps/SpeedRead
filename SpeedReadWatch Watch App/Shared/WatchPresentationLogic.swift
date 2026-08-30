import Foundation
import Observation

struct WatchRSVPPositionCommit: Equatable {
    let bookId: UUID
    let bookTitle: String
    let wordIndex: Int
}

@Observable
@MainActor
final class WatchRSVPSession {
    let engine: RSVPEngine
    private var didCommitDismiss = false

    init() {
        engine = RSVPEngine()
    }

    init(engine: RSVPEngine) {
        self.engine = engine
    }

    func load(book: WatchBook?, wpm: Int) -> Double {
        didCommitDismiss = false
        guard let book else {
            engine.stop()
            return 0
        }
        engine.load(words: book.words, startingAt: book.lastReadIndex)
        engine.wpm = wpm
        return CrownSeek.crownValue(forWordIndex: book.lastReadIndex, wordCount: book.words.count)
    }

    func togglePlayback() {
        engine.togglePlayPause()
    }

    func togglePlayback(book: WatchBook?, now: Date = Date()) -> WatchRSVPPositionCommit? {
        engine.togglePlayPause()
        return nil
    }

    func commitPlaybackAdvanceIfNeeded(
        book: WatchBook?,
        now: Date = Date()
    ) -> WatchRSVPPositionCommit? {
        nil
    }

    func prepareForSettings() {
        if engine.state == .playing {
            engine.pause()
        }
    }

    func seek(toCrownValue crownValue: Double, wordCount: Int) {
        guard engine.state != .playing else { return }
        engine.seek(to: CrownSeek.wordIndex(forCrownValue: crownValue, wordCount: wordCount))
    }

    func close(book: WatchBook?) -> WatchRSVPPositionCommit? {
        let commit = positionCommit(book: book)
        didCommitDismiss = true
        engine.stop()
        return commit
    }

    func handleDisappear(book: WatchBook?) -> WatchRSVPPositionCommit? {
        guard !didCommitDismiss else {
            engine.stop()
            return nil
        }
        let commit = positionCommit(book: book)
        engine.stop()
        return commit
    }

    private func positionCommit(book: WatchBook?) -> WatchRSVPPositionCommit? {
        guard let book, engine.isLoaded else { return nil }
        return WatchRSVPPositionCommit(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: engine.snapshotIndexAndPause()
        )
    }
}

enum WatchBookDetailLogic {
    static func readingActionTitle(lastReadIndex: Int) -> String {
        lastReadIndex > 0 ? "Continue Reading" : "Read"
    }

    static func select(_ book: WatchBook, in library: inout WatchLibrary) {
        library.setCurrentBook(id: book.id)
    }

    static func remove(_ book: WatchBook, from library: inout WatchLibrary) {
        library.removeBook(id: book.id)
    }
}

enum WatchLibraryLogic {
    enum PresentationState: Equatable {
        case receiving
        case empty
        case books
    }

    static func state(isReceiving: Bool, library: WatchLibrary) -> PresentationState {
        if isReceiving { return .receiving }
        return library.books.isEmpty ? .empty : .books
    }

    static func removeBooks(at offsets: IndexSet, from library: inout WatchLibrary) {
        let sorted = library.sortedBooks
        for index in offsets where sorted.indices.contains(index) {
            library.removeBook(id: sorted[index].id)
        }
    }
}

enum WatchSettingsLogic {
    enum Row: Equatable {
        case backToReadingPosition
        case speed
    }

    static var rows: [Row] {
        // Red-phase scaffold. The recall row lands after the red test is observed.
        [.speed]
    }

    static func snappedWPM(_ value: Double) -> Int {
        Int((value / 10).rounded() * 10)
    }

    @discardableResult
    static func apply(_ value: Double, to engine: RSVPEngine) -> Int {
        let wpm = snappedWPM(value)
        engine.wpm = wpm
        return wpm
    }
}
