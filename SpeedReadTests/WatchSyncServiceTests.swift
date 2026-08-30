import Foundation
import SwiftData
import Testing
import WatchConnectivity
@testable import SpeedRead

@Suite("Watch sync service seam")
@MainActor
struct WatchSyncServiceTests {
    @Test func injectedSessionIsActivatedAndReceivesTheDelegate() {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)

        service.activate()

        #expect(connection.delegate === service)
        #expect(connection.activationCount == 1)
    }

    @Test func activeSessionPublishesReadingPositionThroughTheInjectedConnection() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 4_000)

        service.syncReadingPosition(
            bookId: id,
            bookTitle: "Book",
            wordIndex: 17,
            timestamp: timestamp
        )

        let context = try #require(connection.applicationContexts.first)
        let payload = try #require(WatchSyncLogic.PositionPayload.decode(from: context))
        #expect(payload == .init(
            bookId: id,
            bookTitle: "Book",
            wordIndex: 17,
            timestamp: timestamp,
            furthestReadWordIndex: 17
        ))
    }

    @Test func inactiveSessionDoesNotPublishAReadingPosition() {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .inactive
        let service = WatchSyncService(session: connection)

        service.syncReadingPosition(bookId: UUID(), bookTitle: "Book", wordIndex: 4)

        #expect(connection.applicationContexts.isEmpty)
    }

    @Test func reachableWatchUsesMessageDeliveryAndHandlesTheReply() async {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        connection.isReachable = true
        connection.messageResult = .reply(["status": "ok"])
        let service = WatchSyncService(session: connection)

        service.sendBook(id: UUID(), title: "Delivered", author: "Author", text: "one two", wordCount: 2)
        await Task.yield()

        #expect(connection.messages.count == 1)
        #expect(connection.files.isEmpty)
        #expect(service.sendState == .sent("Delivered"))
    }

    @Test func unreachableWatchUsesFileTransferThroughTheInjectedConnection() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        connection.isReachable = false
        let service = WatchSyncService(session: connection)

        service.sendBook(id: UUID(), title: "Queued", author: "Author", text: "one two", wordCount: 2)

        let transfer = try #require(connection.files.first)
        #expect(try String(contentsOf: transfer.url, encoding: .utf8) == "one two")
        #expect(transfer.metadata?["title"] as? String == "Queued")
        #expect(connection.messages.isEmpty)
    }

    @Test func messageFailureFallsBackToFileTransfer() async {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        connection.isReachable = true
        connection.messageResult = .failure(FakeConnectionError.failed)
        let service = WatchSyncService(session: connection)

        service.sendBook(id: UUID(), title: "Fallback", author: "Author", text: "body", wordCount: 1)
        for _ in 0..<10 where connection.files.isEmpty {
            await Task.yield()
        }

        #expect(connection.messages.count == 1)
        #expect(connection.files.count == 1)
    }

    @Test func delegateDeactivationReactivatesTheInjectedConnection() {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)

        service.sessionDidDeactivate(.default)

        #expect(connection.activationCount == 1)
    }

    @Test func delegateMessagePathRejectsMalformedPayloadAndAcceptsARealBook() {
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        var replies: [[String: Any]] = []

        service.session(.default, didReceiveMessage: ["title": "missing fields"]) {
            replies.append($0)
        }
        service.session(
            .default,
            didReceiveMessage: WatchSyncLogic.BookPayload(
                id: UUID(), title: "Book", author: "Author", text: "body", wordCount: 1
            ).dictionary
        ) {
            replies.append($0)
        }

        #expect(replies.count == 2)
        #expect(replies[0]["status"] as? String == "error")
        #expect(replies[1]["status"] as? String == "ok")
    }

    @Test func delegateApplicationContextOffersNewerPositionWithoutApplyingIt() async throws {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: configuration
        )
        let book = Book(
            title: "Stored",
            author: "Author",
            extractedText: (0..<1_000).map { "word\($0)" }.joined(separator: " "),
            sourceFileName: "stored.txt"
        )
        book.lastReadDate = Date(timeIntervalSince1970: 100)
        book.furthestReadWordIndex = 1
        container.mainContext.insert(book)
        try container.mainContext.save()
        service.configure(modelContext: container.mainContext)
        let payload = WatchSyncLogic.PositionPayload(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 99,
            timestamp: Date(timeIntervalSince1970: 200),
            furthestReadWordIndex: 80
        )

        service.session(.default, didReceiveApplicationContext: payload.dictionary)
        for _ in 0..<20 where service.pendingWatchPositionOffer == nil {
            await Task.yield()
        }

        #expect(book.lastReadWordIndex == 0)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 100))
        #expect(book.furthestReadWordIndex == 80)
        #expect(service.pendingWatchPositionOffer?.wordIndex == 99)
        let offer = try #require(service.pendingWatchPositionOffer)
        #expect(service.continueFromWatch(offer))
        #expect(book.lastReadWordIndex == 99)
        #expect(book.browseWordIndex == 99)
        #expect(book.lastReadDate == payload.timestamp)
        #expect(service.pendingWatchPositionOffer == nil)
    }

    @Test func staleReadingStillMaxMergesFurthestWithoutCreatingAnOffer() async throws {
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: configuration
        )
        let book = Book(
            title: "Stored",
            author: "Author",
            extractedText: (0..<100).map { "word\($0)" }.joined(separator: " "),
            sourceFileName: "stored.txt"
        )
        book.lastReadWordIndex = 20
        book.lastReadDate = Date(timeIntervalSince1970: 300)
        book.furthestReadWordIndex = 40
        container.mainContext.insert(book)
        try container.mainContext.save()
        service.configure(modelContext: container.mainContext)
        let stale = WatchSyncLogic.PositionPayload(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 5,
            timestamp: Date(timeIntervalSince1970: 200),
            furthestReadWordIndex: 80
        )

        service.session(.default, didReceiveApplicationContext: stale.dictionary)
        for _ in 0..<20 where book.furthestReadWordIndex != 80 {
            await Task.yield()
        }

        #expect(book.lastReadWordIndex == 20)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 300))
        #expect(book.furthestReadWordIndex == 80)
        #expect(service.pendingWatchPositionOffer == nil)
    }

    @Test func watchOfferTextUsesHumanWordNumberAndFormattedProgress() {
        let offer = WatchSyncService.PositionOffer(
            bookId: UUID(),
            bookTitle: "Book",
            wordIndex: 4_119,
            wordCount: 12_000,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        #expect(offer.displayText == "Continue from Apple Watch — 34%, word 4,120")
    }
}

@MainActor
private final class FakeWatchConnectivitySession: WatchConnectivitySession {
    struct Transfer {}

    enum MessageResult {
        case none
        case reply([String: Any])
        case failure(any Error)
    }

    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .notActivated
    var isReachable = false
    var isPaired = true
    var activationCount = 0
    var messages: [[String: Any]] = []
    var files: [(url: URL, metadata: [String: Any]?)] = []
    var applicationContexts: [[String: Any]] = []
    var messageResult: MessageResult = .none

    func activate() {
        activationCount += 1
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {
        messages.append(message)
        switch messageResult {
        case .none:
            break
        case .reply(let reply):
            replyHandler?(reply)
        case .failure(let error):
            errorHandler?(error)
        }
    }

    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer {
        files.append((fileURL, metadata))
        return Transfer()
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContexts.append(applicationContext)
    }
}

private enum FakeConnectionError: Error {
    case failed
}
