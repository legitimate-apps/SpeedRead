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

    @Test func independentlyConstructedOfferIsClampedAndRepairsLegacyMarkersWhenAccepted() async throws {
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
        book.lastReadDate = Date(timeIntervalSince1970: 100)
        container.mainContext.insert(book)
        try container.mainContext.save()
        service.configure(modelContext: container.mainContext)
        let timestamp = Date(timeIntervalSince1970: 200)
        let incoming = WatchSyncLogic.PositionPayload(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: 99,
            timestamp: timestamp,
            furthestReadWordIndex: 99
        )

        service.session(.default, didReceiveApplicationContext: incoming.dictionary)
        for _ in 0..<20 where service.pendingWatchPositionOffer == nil {
            await Task.yield()
        }
        let pending = try #require(service.pendingWatchPositionOffer)
        let independentlyConstructed = WatchSyncService.PositionOffer(
            bookId: pending.bookId,
            bookTitle: pending.bookTitle,
            wordIndex: pending.wordIndex,
            wordCount: pending.wordCount,
            timestamp: pending.timestamp
        )

        // Acceptance must not rely on applyIncomingPosition having kept these valid.
        book.wordCount = 10
        book.browseWordIndex = -1
        book.furthestReadWordIndex = -1

        #expect(service.continueFromWatch(independentlyConstructed))
        #expect(book.lastReadWordIndex == 9)
        #expect(book.browseWordIndex == 9)
        #expect(book.furthestReadWordIndex == 9)
    }

    @Test func inactiveBookSendFailsWithoutEnqueuingDelivery() {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)
        service.sendBook(id: UUID(), title: "Unavailable", author: "", text: "body", wordCount: 1)
        #expect(service.sendState == .failed("Watch not connected"))
        #expect(connection.messages.isEmpty)
        #expect(connection.files.isEmpty)
    }

    @Test func dismissedOfferCannotMoveOrReopenBook() throws {
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: 70, time: 200))
        let offer = try #require(service.pendingWatchPositionOffer)
        book.finishedAt = Date(timeIntervalSince1970: 150)
        service.dismissWatchPositionOffer()
        #expect(service.pendingWatchPositionOffer == nil)
        #expect(!service.continueFromWatch(offer))
        #expect(book.lastReadWordIndex == 20)
        #expect(book.finishedAt == Date(timeIntervalSince1970: 150))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func deletedBookInvalidatesPendingOffer() throws {
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: 70, time: 200))
        let offer = try #require(service.pendingWatchPositionOffer)
        container.mainContext.delete(book)
        try container.mainContext.save()
        #expect(!service.continueFromWatch(offer))
        #expect(service.pendingWatchPositionOffer == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test(arguments: [200.0, 201.0])
    func localReadingAtOrAfterOfferInvalidatesIt(time: Double) throws {
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: 70, time: 200))
        let offer = try #require(service.pendingWatchPositionOffer)
        book.lastReadWordIndex = 25
        book.browseWordIndex = 25
        book.lastReadDate = Date(timeIntervalSince1970: time)
        book.finishedAt = book.lastReadDate
        try container.mainContext.save()
        #expect(!service.continueFromWatch(offer))
        #expect(service.pendingWatchPositionOffer == nil)
        #expect(book.lastReadWordIndex == 25)
        #expect(book.browseWordIndex == 25)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: time))
        #expect(book.finishedAt == book.lastReadDate)
    }

    @Test func replacementOfferRejectsOldValueAndPersistsAcceptedPosition() throws {
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: 70, time: 200))
        let oldOffer = try #require(service.pendingWatchPositionOffer)
        service.applyIncomingPosition(position(book, index: 80, time: 300))
        let newOffer = try #require(service.pendingWatchPositionOffer)
        #expect(!service.continueFromWatch(oldOffer))
        #expect(service.pendingWatchPositionOffer == newOffer)
        #expect(service.continueFromWatch(newOffer))
        let freshContext = ModelContext(container)
        let persisted = try #require(freshContext.fetch(FetchDescriptor<Book>()).first)
        #expect(persisted.lastReadWordIndex == 80)
        #expect(persisted.browseWordIndex == 80)
        #expect(persisted.furthestReadWordIndex == 80)
        #expect(persisted.lastReadDate == Date(timeIntervalSince1970: 300))
    }

    @Test func unconfiguredAndUnknownBookPositionsDoNotCreateOffers() throws {
        let (service, container, book) = try positionFixture()
        let incoming = position(book, index: 70, time: 200)
        let unconfigured = WatchSyncService(session: FakeWatchConnectivitySession())
        unconfigured.applyIncomingPosition(incoming)
        #expect(unconfigured.pendingWatchPositionOffer == nil)
        service.applyIncomingPosition(.init(bookId: UUID(), bookTitle: "Unknown", wordIndex: 70,
                                            timestamp: incoming.timestamp, furthestReadWordIndex: 90))
        #expect(service.pendingWatchPositionOffer == nil)
        #expect(book.furthestReadWordIndex == 20)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func emptyBookOfferFormattingHasNoDivisionByZero() {
        let offer = WatchSyncService.PositionOffer(bookId: UUID(), bookTitle: "Empty", wordIndex: 0,
                                                   wordCount: 0, timestamp: .distantPast)
        #expect(offer.id == offer.bookId)
        #expect(offer.displayText == "Continue from Apple Watch — 0%, word 1")
    }

    @Test("An explicit error reply fails without retrying the rejected payload")
    func rejectedBookReplyFailsWithoutFileFallback() async {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        connection.isReachable = true
        connection.messageResult = .reply(["status": "error"])
        let service = WatchSyncService(session: connection)
        // Negative counts really are rejected by the receiving decoder.
        let payload = WatchSyncLogic.BookPayload(id: UUID(), title: "Rejected", author: "", text: "body", wordCount: -1)
        #expect(WatchSyncLogic.BookPayload.decode(from: payload.dictionary) == nil)
        service.sendBook(id: payload.id, title: payload.title, author: payload.author,
                         text: payload.text, wordCount: payload.wordCount)
        for _ in 0..<50 where service.sendState == .sending("Rejected") { await Task.yield() }
        // A decoder rejection is deterministic; do not retry the same payload as a file.
        #expect(service.sendState == .failed("Apple Watch did not accept the book."))
        #expect(connection.messages.count == 1)
        #expect(connection.files.isEmpty)
    }

    @Test("A delayed older context preserves the newer pending offer")
    func pendingOfferPreservesNewestWhenContextsArriveOutOfOrder() throws {
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: 80, time: 300))
        #expect(service.pendingWatchPositionOffer?.wordIndex == 80)
        service.applyIncomingPosition(position(book, index: 60, time: 200))
        let offer = try #require(service.pendingWatchPositionOffer)
        #expect(offer.wordIndex == 80)
        #expect(offer.timestamp == Date(timeIntervalSince1970: 300))
        #expect(service.continueFromWatch(offer))
        #expect(book.lastReadWordIndex == 80)
        #expect(book.furthestReadWordIndex == 80)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test(arguments: ["missing", "type", "unknown"])
    func malformedBookRepliesFailWithoutFileFallback(kind: String) async {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        connection.isReachable = true
        let reply: [String: Any] = kind == "missing" ? [:]
            : ["status": kind == "type" ? 1 as Any : "unexpected" as Any]
        connection.messageResult = .reply(reply)
        let service = WatchSyncService(session: connection)
        service.sendBook(id: UUID(), title: "Malformed", author: "", text: "body", wordCount: 1)
        for _ in 0..<50 where service.sendState == .sending("Malformed") { await Task.yield() }
        #expect(service.sendState == .failed("Apple Watch did not accept the book."))
        #expect(connection.messages.count == 1)
        #expect(connection.files.isEmpty)
    }

    @Test func positionDecoderRejectsNegativeButAcceptsZero() throws {
        // Mutation caught: deleting wordIndex >= 0, or changing it to wordIndex > 0.
        let id = UUID()
        let negative = WatchSyncLogic.PositionPayload(
            bookId: id, bookTitle: "Boundary", wordIndex: -1,
            timestamp: Date(timeIntervalSince1970: 200))
        #expect(WatchSyncLogic.PositionPayload.decode(from: negative.dictionary) == nil)
        var zero = negative.dictionary
        zero["wordIndex"] = 0
        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: zero))
        #expect(decoded.wordIndex == 0)
        #expect(decoded.bookId == id)
    }

    @Test func directlyConstructedNegativePositionCannotProduceNegativeOffer() throws {
        // Mutation caught: omitting the lower bound when constructing an incoming offer.
        // Direct callers are not protected by the transport decoder.
        let (service, container, book) = try positionFixture()
        service.applyIncomingPosition(position(book, index: -1, time: 200))
        let offer = try #require(service.pendingWatchPositionOffer)
        #expect(offer.wordIndex == 0)
        #expect(book.lastReadWordIndex == 20)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test(arguments: [-100, 1000])
    func incomingOfferAndHighWaterClampBothSides(index: Int) throws {
        // Mutation: remove either ingress offer bound, or the high-water upper bound.
        let (service, container, book) = try positionFixture()
        book.furthestReadWordIndex = index
        service.applyIncomingPosition(position(book, index: index, time: 200))
        let expected = index < 0 ? 0 : 99
        #expect(service.pendingWatchPositionOffer?.wordIndex == expected)
        // Legacy migration raises a negative high-water to the existing reading index (20).
        #expect(book.furthestReadWordIndex == (index < 0 ? 20 : 99))
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        #expect(saved.furthestReadWordIndex == book.furthestReadWordIndex)
    }

    @Test(arguments: [-100, 1000])
    func acceptanceIndependentlyClampsBothSides(index: Int) throws {
        // Mutation: remove either acceptance bound; an ingress clamp must not mask this test.
        let (_, container, book) = try positionFixture()
        let offer = WatchSyncService.PositionOffer(bookId: book.id, bookTitle: book.title,
            wordIndex: index, wordCount: book.wordCount, timestamp: Date(timeIntervalSince1970: 200))
        let service = WatchSyncService(session: FakeWatchConnectivitySession(), pendingOffer: offer)
        service.configure(modelContext: container.mainContext)
        book.furthestReadWordIndex = index
        #expect(service.continueFromWatch(offer))
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        let expected = index < 0 ? 0 : 99
        #expect(saved.lastReadWordIndex == expected)
        #expect(saved.browseWordIndex == expected)
        #expect(saved.furthestReadWordIndex == (index < 0 ? 20 : 99))
        #expect(service.pendingWatchPositionOffer == nil)
    }

    @Test(arguments: ["Transferred", ""])
    func fileCompletionReportsTitleAndFallback(title: String) async {
        // Mutation: never mark a finished transfer sent, or drop the metadata/default title.
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        service.session(.default, didFinish: WatchFileTransferFixture(metadata: title.isEmpty ? nil : ["title": title]), error: nil)
        for _ in 0..<50 where service.sendState == .idle { await Task.yield() }
        #expect(service.sendState == .sent(title.isEmpty ? "Book" : title))
    }

    @Test func fileCompletionFailureReportsErrorThenClears() async throws {
        // Mutation: treat an error as success, discard its description, or omit delayed clearing.
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        let error = NSError(domain: "TransferTest", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Transfer interrupted"])
        service.session(.default, didFinish: WatchFileTransferFixture(metadata: ["title": "Failed"]), error: error)
        for _ in 0..<50 where service.sendState == .idle { await Task.yield() }
        #expect(service.sendState == .failed("Transfer interrupted"))
        try await Task.sleep(for: .milliseconds(2800))
        #expect(service.sendState == .idle)
    }

    private func positionFixture() throws -> (WatchSyncService, ModelContainer, Book) {
        let container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "Position", author: "", extractedText: (0..<100).map { "word\($0)" }.joined(separator: " "), sourceFileName: "position.txt")
        book.lastReadWordIndex = 20
        book.browseWordIndex = 20
        book.furthestReadWordIndex = 20
        book.lastReadDate = Date(timeIntervalSince1970: 100)
        container.mainContext.insert(book)
        try container.mainContext.save()
        let service = WatchSyncService(session: FakeWatchConnectivitySession())
        service.configure(modelContext: container.mainContext)
        return (service, container, book)
    }

    private func position(_ book: Book, index: Int, time: Double) -> WatchSyncLogic.PositionPayload {
        .init(bookId: book.id, bookTitle: book.title, wordIndex: index,
              timestamp: Date(timeIntervalSince1970: time), furthestReadWordIndex: index)
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
final class FakeWatchConnectivitySession: WatchConnectivitySession {
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
