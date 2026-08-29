import Foundation
import Testing
import WatchConnectivity
@testable import SpeedReadWatch_Watch_App

@Suite("Watch sync delegate characterization")
@MainActor
struct WatchSyncServiceCharacterizationTests {
    @Test("Characterization: activation installs the delegate on the injected session")
    func activationUsesInjectedSession() {
        let connection = FakeWatchSession()
        let service = WatchSyncService(session: connection)

        service.activate()

        #expect(connection.delegate === service)
        #expect(connection.activationCount == 1)
    }

    @Test("Characterization: local position updates both the library and application context")
    func outboundPositionUpdatesLibraryAndConnection() throws {
        let book = makeBook(index: 0, timestamp: nil)
        let connection = FakeWatchSession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let timestamp = Date(timeIntervalSince1970: 300)

        service.syncReadingPosition(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 2,
            timestamp: timestamp
        )

        #expect(service.library.currentBook?.lastReadIndex == 2)
        #expect(service.library.currentBook?.lastReadDate == timestamp)
        let context = try #require(connection.applicationContexts.first)
        #expect(WatchSyncLogic.PositionPayload.decode(from: context)?.wordIndex == 2)
    }

    @Test("Characterization: delegate application context applies a newer known position")
    func delegateAppliesNewPosition() async {
        let book = makeBook(index: 0, timestamp: Date(timeIntervalSince1970: 100))
        let service = WatchSyncService(session: FakeWatchSession())
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let payload = WatchSyncLogic.PositionPayload(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 99,
            timestamp: Date(timeIntervalSince1970: 200)
        )

        service.session(.default, didReceiveApplicationContext: payload.dictionary)
        await waitUntil { service.library.currentBook?.lastReadDate == payload.timestamp }

        #expect(service.library.currentBook?.lastReadIndex == 2)
        #expect(service.library.currentBook?.lastReadDate == payload.timestamp)
    }

    @Test("Characterization: delegate application context rejects stale and malformed positions")
    func delegateRejectsStaleAndMalformedPositions() async {
        let savedDate = Date(timeIntervalSince1970: 200)
        let book = makeBook(index: 1, timestamp: savedDate)
        let service = WatchSyncService(session: FakeWatchSession())
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let stale = WatchSyncLogic.PositionPayload(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 2,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        service.session(.default, didReceiveApplicationContext: stale.dictionary)
        service.session(.default, didReceiveApplicationContext: ["bookId": "bad"])
        await Task.yield()

        #expect(service.library.currentBook?.lastReadIndex == 1)
        #expect(service.library.currentBook?.lastReadDate == savedDate)
    }

    @Test("Characterization: delegate message rejects malformed books")
    func delegateRejectsMalformedMessage() {
        let service = WatchSyncService(session: FakeWatchSession())
        var reply: [String: Any] = [:]

        service.session(.default, didReceiveMessage: ["title": "missing fields"]) {
            reply = $0
        }

        #expect(reply["status"] as? String == "error")
        #expect(service.library.books.isEmpty)
    }

    @Test("Characterization: delegate message acknowledges and ingests a real book")
    func delegateIngestsBookMessage() async {
        let service = WatchSyncService(session: FakeWatchSession())
        let payload = WatchSyncLogic.BookPayload(
            id: UUID(), title: "Received", author: "Author", text: "zero one", wordCount: 2
        )
        var reply: [String: Any] = [:]

        service.session(.default, didReceiveMessage: payload.dictionary) {
            reply = $0
        }
        await waitUntil { service.library.books.count == 1 }

        #expect(reply["status"] as? String == "ok")
        #expect(service.library.currentBook?.id == payload.id)
        #expect(service.library.currentBook?.text == payload.text)
    }

    @Test("Characterization: duplicate delegate message does not duplicate a book")
    func delegateIgnoresDuplicateBookMessage() async {
        let service = WatchSyncService(session: FakeWatchSession())
        let payload = WatchSyncLogic.BookPayload(
            id: UUID(), title: "Received", author: "Author", text: "zero one", wordCount: 2
        )

        service.session(.default, didReceiveMessage: payload.dictionary) { _ in }
        await waitUntil { service.library.books.count == 1 }
        service.session(.default, didReceiveMessage: payload.dictionary) { _ in }
        await Task.yield()

        #expect(service.library.books.count == 1)
        #expect(service.isReceiving == false)
        #expect(service.receivingTitle == nil)
    }

    private func makeBook(index: Int, timestamp: Date?) -> WatchBook {
        WatchBook(
            id: UUID(),
            title: "Watch Book",
            author: "Author",
            text: "zero one two",
            lastReadIndex: index,
            lastReadDate: timestamp,
            wordCount: 3,
            dateAdded: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func waitUntil(attempts: Int = 50, condition: @MainActor () -> Bool) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeWatchSession: WatchConnectivitySession {
    struct Transfer {}

    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .notActivated
    var isReachable = false
    var activationCount = 0
    var applicationContexts: [[String: Any]] = []

    func activate() {
        activationCount += 1
    }

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
