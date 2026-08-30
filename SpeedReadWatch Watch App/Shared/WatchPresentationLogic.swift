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
    private var positionCommitPolicy = PlaybackPositionCommitPolicy()
    private var lastCrownValue: Double = 0

    init() {
        engine = RSVPEngine()
    }

    init(engine: RSVPEngine) {
        self.engine = engine
    }

    func load(book: WatchBook?, wpm: Int) -> Double {
        didCommitDismiss = false
        positionCommitPolicy.reset()
        guard let book else {
            engine.stop()
            return 0
        }
        engine.load(words: book.words, startingAt: book.browseWordIndex)
        engine.wpm = wpm
        let crownValue = CrownSeek.crownValue(
            forWordIndex: book.browseWordIndex,
            wordCount: book.words.count
        )
        lastCrownValue = crownValue
        return crownValue
    }

    func togglePlayback() {
        engine.togglePlayPause()
    }

    func togglePlayback(book: WatchBook?, now: Date = Date()) -> WatchRSVPPositionCommit? {
        if engine.state == .playing {
            engine.pause()
            return nil
        }
        guard let book, engine.isLoaded else { return nil }
        let index = engine.currentIndex
        engine.play()
        positionCommitPolicy.pressedPlay(at: index, now: now)
        return makePositionCommit(book: book, index: index)
    }

    func commitPlaybackAdvanceIfNeeded(
        book: WatchBook?,
        now: Date = Date()
    ) -> WatchRSVPPositionCommit? {
        guard let book,
              engine.state == .playing,
              positionCommitPolicy.shouldCommitAdvance(at: engine.currentIndex, now: now) else {
            return nil
        }
        return makePositionCommit(book: book, index: engine.currentIndex)
    }

    func prepareForSettings() {
        if engine.state == .playing {
            engine.pause()
        }
    }

    @discardableResult
    func seek(toCrownValue crownValue: Double, wordCount: Int) -> Double {
        guard engine.state != .playing else { return lastCrownValue }
        let crownDelta = crownValue - lastCrownValue
        let target = engine.currentIndex - Int(crownDelta.rounded())
        engine.seek(to: target)
        return synchronizeCrownValue(wordCount: wordCount)
    }

    func synchronizeCrownValue(wordCount: Int) -> Double {
        let crownValue = CrownSeek.crownValue(
            forWordIndex: engine.currentIndex,
            wordCount: wordCount
        )
        lastCrownValue = crownValue
        return crownValue
    }

    func restoreReadingPosition(book: WatchBook) -> Double {
        engine.pause()
        engine.seek(to: book.lastReadIndex)
        return synchronizeCrownValue(wordCount: book.words.count)
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
        let index = engine.snapshotIndexAndPause()
        guard positionCommitPolicy.hasPlayed else { return nil }
        return makePositionCommit(book: book, index: index)
    }

    private func makePositionCommit(book: WatchBook, index: Int) -> WatchRSVPPositionCommit {
        WatchRSVPPositionCommit(bookId: book.id, bookTitle: book.title, wordIndex: index)
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
        [.backToReadingPosition, .speed]
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
