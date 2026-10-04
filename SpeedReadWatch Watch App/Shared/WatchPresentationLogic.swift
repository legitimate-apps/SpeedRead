import Foundation
import Observation

struct WatchRSVPPositionCommit: Equatable {
    let bookId: UUID
    let bookTitle: String
    let wordIndex: Int
    var didFinish: Bool = false
}

@Observable
@MainActor
final class WatchRSVPSession {
    let engine: RSVPEngine
    private var didCommitDismiss = false
    private var positionCommitPolicy = PlaybackPositionCommitPolicy()
    private var lastCrownValue: Double = 0

    /// The loaded token stream's length. Crown math must use this, not `WatchBook.wordCount`:
    /// it is what the engine actually displays, and it costs nothing to read per word.
    var wordCount: Int { engine.totalWords }

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
        engine.load(words: book.tokenizeWords(), startingAt: book.browseWordIndex)
        engine.wpm = wpm
        return synchronizeCrownValue()
    }

    func togglePlayback() {
        engine.togglePlayPause()
    }

    func togglePlayback(book: WatchBook?, now: Date = Date()) -> WatchRSVPPositionCommit? {
        if engine.state == .playing {
            // Pausing is the handoff moment: the word you stopped on becomes the place everywhere.
            let index = engine.snapshotIndexAndPause()
            guard let book else { return nil }
            return makePositionCommit(book: book, index: index)
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
        if let book, engine.didFinish {
            return makePositionCommit(book: book, index: engine.currentIndex)
        }
        guard let book,
              engine.state == .playing,
              positionCommitPolicy.shouldCommitAdvance(at: engine.currentIndex, now: now) else {
            return nil
        }
        return makePositionCommit(book: book, index: engine.currentIndex)
    }

    @discardableResult
    func seek(toCrownValue crownValue: Double) -> Double {
        guard engine.state != .playing else { return lastCrownValue }
        let crownDelta = crownValue - lastCrownValue
        let target = engine.currentIndex - Int(crownDelta.rounded())
        engine.seek(to: target)
        return synchronizeCrownValue()
    }

    func synchronizeCrownValue() -> Double {
        let crownValue = CrownSeek.crownValue(
            forWordIndex: engine.currentIndex,
            wordCount: wordCount
        )
        lastCrownValue = crownValue
        return crownValue
    }

    /// The value the crown binding should take for the visible word, or nil while playing.
    /// Writing the binding makes watchOS rebuild the crown's detent notches across the whole
    /// range, so a per-word write costs O(book) per word; the crown is inert during playback
    /// anyway (`seek` ignores it). `lastCrownValue` still tracks every word, so the first detent
    /// after a pause moves from the visible word.
    func crownValueToPublish() -> Double? {
        let crownValue = synchronizeCrownValue()
        return engine.state == .playing ? nil : crownValue
    }

    func restoreReadingPosition(book: WatchBook) -> Double {
        engine.pause()
        engine.seek(to: book.lastReadIndex)
        return synchronizeCrownValue()
    }

    /// The phone moved the place: show its word, unless this watch is the one reading.
    func follow(placeAt index: Int) -> Double? {
        guard engine.state != .playing, engine.isLoaded, index != engine.currentIndex else { return nil }
        engine.seek(to: index)
        return synchronizeCrownValue()
    }

    /// The phone took the book over: stop without committing, at the phone's word.
    func yield(to presence: RemotePresence) -> Double {
        engine.pause()
        engine.seek(to: presence.wordIndex)
        return synchronizeCrownValue()
    }

    func browse(to chapter: ChapterMark, in book: WatchBook) -> Double {
        engine.pause()
        engine.seek(to: chapter.startWordIndex)
        return synchronizeCrownValue()
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
        WatchRSVPPositionCommit(bookId: book.id, bookTitle: book.title, wordIndex: index,
                                didFinish: engine.didFinish)
    }
}

enum WatchChapterSelection {
    @MainActor
    static func browse(
        to chapter: ChapterMark,
        in book: WatchBook,
        session: WatchRSVPSession,
        library: inout WatchLibrary
    ) -> Double {
        let crownValue = session.browse(to: chapter, in: book)
        library.updateBrowsePosition(
            bookId: book.id,
            index: session.engine.currentIndex
        )
        return crownValue
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
