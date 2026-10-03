import Foundation
import Testing
import WatchConnectivity
@testable import SpeedReadWatch_Watch_App

@Suite("Watch three-marker position model")
@MainActor
struct WatchPositionModelTests {
    private let storage: WatchTestStorage

    init() throws {
        storage = try WatchTestStorage()
    }

    @Test func legacyPersistedBookInitializesNewMarkersFromReadingPosition() throws {
        let legacy = LegacyWatchBook(
            id: UUID(),
            title: "Legacy",
            author: "Author",
            text: "zero one two three",
            lastReadIndex: 2,
            lastReadDate: Date(timeIntervalSince1970: 100),
            wordCount: 4,
            dateAdded: Date(timeIntervalSince1970: 50)
        )

        let decoded = try JSONDecoder().decode(
            WatchBook.self,
            from: JSONEncoder().encode(legacy)
        )

        #expect(decoded.lastReadIndex == 2)
        #expect(decoded.browseWordIndex == 2)
        #expect(decoded.furthestReadWordIndex == 2)
        #expect(decoded.chapters.isEmpty)
        #expect(!decoded.hasFinishedLocally)
        #expect(decoded.progress == 0.5)
    }

    @Test func browsingOnWatchPublishesNothingAndCannotAlterReadingPosition() {
        let connection = BrowseRecordingWatchSession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection, store: storage.store)
        let readDate = Date(timeIntervalSince1970: 200)
        let book = WatchBook(
            id: UUID(),
            title: "Book",
            author: "Author",
            text: "zero one two three",
            lastReadIndex: 1,
            lastReadDate: readDate,
            browseWordIndex: 1,
            furthestReadWordIndex: 3,
            wordCount: 4,
            dateAdded: Date(timeIntervalSince1970: 100)
        )
        service.library = WatchLibrary(books: [book], currentBookId: book.id)

        let updated = service.library.updateBrowsePosition(bookId: book.id, index: 3)
        let movedBackward = service.library.updateBrowsePosition(bookId: book.id, index: 0)

        #expect(updated)
        #expect(movedBackward)
        #expect(service.library.currentBook?.browseWordIndex == 0)
        #expect(service.library.currentBook?.lastReadIndex == 1)
        #expect(service.library.currentBook?.lastReadDate == readDate)
        #expect(service.library.currentBook?.furthestReadWordIndex == 3)
        #expect(connection.applicationContexts.isEmpty)
    }

    @Test func watchBookPersistsChapterMarks() throws {
        let chapters = [
            ChapterMark(title: "Start", startWordIndex: 0),
            ChapterMark(title: "Part Two", startWordIndex: 2)
        ]
        let book = WatchBook(
            id: UUID(), title: "Book", author: "Author", text: "zero one two three",
            lastReadIndex: 0, lastReadDate: nil, wordCount: 4,
            dateAdded: Date(timeIntervalSince1970: 100), chapters: chapters
        )

        let decoded = try JSONDecoder().decode(
            WatchBook.self,
            from: JSONEncoder().encode(book)
        )

        #expect(decoded.chapters == chapters)
    }

    @Test func watchWordsUseTheCanonicalHyphenTokenCoordinates() {
        let book = WatchBook(
            id: UUID(), title: "Book", author: "Author",
            text: "self-awareness starts part-two",
            lastReadIndex: 0, lastReadDate: nil, wordCount: 5,
            dateAdded: Date(timeIntervalSince1970: 100),
            chapters: [ChapterMark(title: "Part", startWordIndex: 3)]
        )

        let words = book.tokenizeWords()
        #expect(words == ["self-", "awareness", "starts", "part-", "two"])
        #expect(words[book.chapters[0].startWordIndex] == "part-")
    }

    @Test("legacy single-book migration stores the canonical token count")
    func legacySingleBookMigrationCountsCanonicalTokens() throws {
        let legacyURL = storage.directory.appendingPathComponent("watchbook.json")
        try JSONSerialization.data(withJSONObject: [
            "title": "Old", "author": "Author", "text": "self-aware zero one", "position": 3,
        ]).write(to: legacyURL)
        let service = WatchSyncService(session: BrowseRecordingWatchSession(), store: storage.store)

        service.loadLibrary()

        let book = try #require(service.library.currentBook)
        // A whitespace count (3) would clamp every later commit off the last token.
        #expect(book.wordCount == 4)
        #expect(book.wordCount == book.tokenizeWords().count)
        #expect(storage.store.load().currentBook?.wordCount == 4)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }
}

private struct LegacyWatchBook: Codable {
    let id: UUID
    let title: String
    let author: String
    let text: String
    let lastReadIndex: Int
    let lastReadDate: Date?
    let wordCount: Int
    let dateAdded: Date
}

@MainActor
private final class BrowseRecordingWatchSession: WatchConnectivitySession {
    struct Transfer {}

    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .notActivated
    var isReachable = false
    var applicationContexts: [[String: Any]] = []

    func activate() {}

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {}

    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer {
        Transfer()
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContexts.append(applicationContext)
    }
}
