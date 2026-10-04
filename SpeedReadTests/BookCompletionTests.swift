import Foundation
import SwiftData
import Testing
import WatchConnectivity
@testable import SpeedRead

@Suite("Book completion")
@MainActor
struct BookCompletionTests {
    @Test(arguments: [false, true])
    func finishingRSVPPersistsAndReturnsToFinishedReader(disappear: Bool) async throws {
        let book = makeBook()
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        let saver = CompletionSaver()
        let sync = CompletionSync()
        try await finish(book, session: session, engine: engine, saver: saver, sync: sync)
        let commit = disappear
            ? session.handleDisappear(engine: engine, book: book, saver: saver, sync: sync)
            : session.close(engine: engine, book: book, saver: saver, sync: sync)
        #expect(commit?.didSave == true)
        #expect(book.lastReadWordIndex == 3)
        #expect(book.progress == 1)
        #expect(ReaderView.readingEstimate(book: book, lastWPM: 250) == "100% · finished")
        let reader = ReaderSession()
        reader.load(book: book)
        reader.reconcileRSVPDismiss(for: book)
        #expect(reader.consumePendingScroll() == 3)
        _ = session.handleDisappear(engine: engine, book: book, saver: saver, sync: sync)
        #expect(book.progress == 1)
    }

    @Test func naturalFinishCommitsWithoutWaitingForDismissal() async throws {
        let book = makeBook()
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        let saver = CompletionSaver()
        let sync = CompletionSync()
        try await finish(book, session: session, engine: engine, saver: saver, sync: sync)
        let commit = session.commitPlaybackAdvanceIfNeeded(engine: engine, book: book, saver: saver, sync: sync)
        #expect(commit?.didSave == true)
        #expect(book.progress == 1)
        #expect(ReaderView.readingEstimate(book: book, lastWPM: 250) == "100% · finished")
    }

    @Test func replayClearsEngineCompletionUntilFinalWordFinishesAgain() async throws {
        let book = makeBook()
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        let saver = CompletionSaver()
        let sync = CompletionSync()
        try await finish(book, session: session, engine: engine, saver: saver, sync: sync)
        _ = session.commitPlaybackAdvanceIfNeeded(engine: engine, book: book, saver: saver, sync: sync)
        _ = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)
        #expect(!engine.didFinish)
        #expect(book.progress == 0.75)
        engine.pause()
        #expect(engine.state == .paused)
    }

    @Test func rereadingClearsCompletionButBrowsingDoesNot() async throws {
        let book = makeBook()
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        let saver = CompletionSaver()
        let sync = CompletionSync()
        try await finish(book, session: session, engine: engine, saver: saver, sync: sync)
        _ = session.close(engine: engine, book: book, saver: saver, sync: sync)
        #expect(book.progress == 1)
        session.load(book: book, engine: engine, wpm: 250)
        #expect(session.recordBrowsePosition(1, book: book, saver: saver))
        #expect(session.close(engine: engine, book: book, saver: saver, sync: sync) == nil)
        #expect(book.progress == 1)
        let reader = ReaderSession()
        reader.load(book: book)
        _ = reader.commitReadingPosition(1, book: book, saver: saver, sync: sync)
        #expect(book.progress == 0.25)
        #expect(ReaderView.readingEstimate(book: book, lastWPM: 250) == "25% · <1 min left at 250 WPM")
        #expect(book.furthestReadWordIndex == 3)
    }

    @Test func completionSurvivesReopeningDiskStore() async throws {
        let url = URL.documentsDirectory.appending(path: "completion-\(UUID()).store")
        defer { removeStore(url) }
        let id = try await writeCompletedBook(to: url)
        let container = try container(at: url)
        let book = try #require(container.mainContext.fetch(FetchDescriptor<Book>()).first)
        #expect(book.id == id)
        #expect(book.words == ["zero", "one", "two", "three"])
        #expect(book.lastReadWordIndex == 3)
        #expect(book.progress == 1)
        #expect(ReaderView.readingEstimate(book: book, lastWPM: 250) == "100% · finished")
    }

    @Test func adoptingWatchPositionStartsReread() async throws {
        let container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "Watch reread", author: "Author",
            extractedText: Array(repeating: "word", count: 40).joined(separator: " "), sourceFileName: "watch.txt")
        container.mainContext.insert(book)
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        try await finish(book, session: session, engine: engine, saver: container.mainContext, sync: CompletionSync())
        _ = session.close(engine: engine, book: book, saver: container.mainContext, sync: CompletionSync())
        #expect(book.progress == 1)
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        service.configure(modelContext: container.mainContext)
        let payload = WatchSyncLogic.PositionPayload(bookId: book.id, bookTitle: book.title,
            wordIndex: 10, timestamp: Date().addingTimeInterval(10))
        service.session(.default, didReceiveApplicationContext: payload.dictionary)
        for _ in 0..<100 where book.lastReadWordIndex != 10 { await Task.yield() }
        #expect(book.progress == 0.25)
    }

    @Test func unopenedAndFinalWordJumpRemainUnfinished() {
        let book = makeBook()
        #expect(book.progress == 0)
        let reader = ReaderSession()
        reader.load(book: book)
        _ = reader.handleWordTap(at: Int.max, book: book, saver: CompletionSaver(), sync: CompletionSync())
        #expect(book.lastReadWordIndex == 3)
        #expect(book.progress == 0.75)
        #expect(ReaderView.readingEstimate(book: book, lastWPM: 250) == "75% · <1 min left at 250 WPM")
    }

    @Test func preCompletionLibraryMigratesWithoutLosingContent() throws {
        let fixture = try #require(Bundle(for: CompletionBundleMarker.self)
            .url(forResource: "PreCompletion", withExtension: "store"))
        let url = URL.documentsDirectory.appending(path: "migration-\(UUID()).store")
        defer { removeStore(url) }
        try FileManager.default.copyItem(at: fixture, to: url)
        let container = try container(at: url)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 2)
        let book = try #require(books.first { $0.title == "Legacy" })
        #expect(book.author == "Author")
        #expect(book.extractedText == "zero one two three")
        #expect(book.sourceFileName == "legacy.txt")
        #expect(book.words == ["zero", "one", "two", "three"])
        #expect(book.lastReadWordIndex == 3)
        #expect(book.browseWordIndex == 2)
        #expect(book.furthestReadWordIndex == 3)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 123))
        #expect(book.progress == 0.75)
        #expect(book.chapters == [ChapterMark(title: "Opening", startWordIndex: 0)])
        let bookmark = try #require(book.bookmarks.first)
        #expect(book.bookmarks.count == 1)
        #expect(bookmark.wordIndex == 1)
        #expect(bookmark.previewText == "one")
        #expect(bookmark.book?.id == book.id)
        let highlight = try #require(book.highlights.first)
        #expect(book.highlights.count == 1)
        #expect(highlight.startWordIndex == 1)
        #expect(highlight.endWordIndex == 2)
        #expect(highlight.highlightedText == "one two")
        #expect(highlight.book?.id == book.id)
        let unopened = try #require(books.first { $0.title == "Unopened" })
        #expect(unopened.progress == 0)
        #expect(unopened.lastReadDate == nil)
        #expect(unopened.words == ["first", "second"])
        try container.mainContext.save()
    }

    private func finish(_ book: Book, session: RSVPPresentationSession, engine: RSVPEngine,
                        saver: any ReadingPositionSaving, sync: any ReadingPositionSyncing) async throws {
        session.load(book: book, engine: engine, wpm: 1500)
        engine.seek(to: book.wordCount - 1)
        _ = session.togglePlayback(engine: engine, book: book, saver: saver, sync: sync)
        let deadline = ContinuousClock.now + .seconds(3)
        while !engine.didFinish && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.didFinish)
    }

    private func writeCompletedBook(to url: URL) async throws -> UUID {
        let container = try container(at: url)
        let book = makeBook()
        container.mainContext.insert(book)
        let session = RSVPPresentationSession()
        let engine = RSVPEngine()
        try await finish(book, session: session, engine: engine, saver: container.mainContext, sync: CompletionSync())
        _ = session.close(engine: engine, book: book, saver: container.mainContext, sync: CompletionSync())
        return book.id
    }

    private func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(url: url))
    }

    private func removeStore(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private func makeBook() -> Book {
        Book(title: "Completion", author: "Author", extractedText: "zero one two three", sourceFileName: "completion.txt")
    }
}

@MainActor
private final class CompletionSaver: ReadingPositionSaving {
    func save() throws {}
}

@MainActor
private final class CompletionSync: ReadingPositionSyncing {
    func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int, timestamp: Date, furthestReadWordIndex: Int, didFinish: Bool, finishedAt: Date?) {}
}

private final class CompletionBundleMarker: NSObject {}
