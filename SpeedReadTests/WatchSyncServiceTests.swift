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
        service.clock = { timestamp }

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

    @Test func delegateDeactivationReactivatesTheInjectedConnection() async {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)

        await Task.detached {
            service.session(.default, activationDidCompleteWith: .activated, error: nil)
            service.sessionDidBecomeInactive(.default)
            service.sessionDidDeactivate(.default)
        }.value
        for _ in 0..<100 where connection.activationCount == 0 { await Task.yield() }

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

    @Test func inactiveBookSendFailsWithoutEnqueuingDelivery() {
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)
        service.sendBook(id: UUID(), title: "Unavailable", author: "", text: "body", wordCount: 1)
        #expect(service.sendState == .failed("Watch not connected"))
        #expect(connection.messages.isEmpty)
        #expect(connection.files.isEmpty)
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
        zero["browseWordIndex"] = 0
        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: zero))
        #expect(decoded.wordIndex == 0)
        #expect(decoded.bookId == id)
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

    // MARK: - The watch's place is adopted, never offered

    @Test func delegateApplicationContextAdoptsANewerWatchPlaceWithoutAsking() async throws {
        let (service, container, book) = try positionFixture()
        let payload = position(book, index: 70, time: 200, furthest: 80)

        service.session(.default, didReceiveApplicationContext: payload.dictionary)
        for _ in 0..<50 where book.lastReadWordIndex != 70 { await Task.yield() }

        #expect(book.lastReadWordIndex == 70)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 200))
        #expect(book.browseWordIndex == 70)
        #expect(book.browseDate == Date(timeIntervalSince1970: 200))
        #expect(book.furthestReadWordIndex == 80)
        let persisted = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        #expect(persisted.lastReadWordIndex == 70)
        #expect(persisted.browseWordIndex == 70)
    }

    @Test func liveMessagesTakeTheSamePathAsContexts() async throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.session(.default, didReceiveMessage: position(book, index: 55, time: 200).dictionary)
        for _ in 0..<50 where book.browseWordIndex != 55 { await Task.yield() }
        #expect(book.browseWordIndex == 55)
    }

    @Test func staleReadingStillMaxMergesFurthestWithoutMovingThePlace() throws {
        // The fixture's place was never moved (browseDate nil), so it dates from the last read
        // at 100. A nil-means-always rule would let this stale place through.
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        #expect(book.browseDate == nil)
        service.receivePosition(position(book, index: 5, time: 50, furthest: 80))
        #expect(book.lastReadWordIndex == 20)
        #expect(book.browseWordIndex == 20)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 100))
        #expect(book.furthestReadWordIndex == 80)
    }

    @Test func aCrownMoveOnTheWatchMovesThePlaceButNotTheReadingPosition() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        // The watch last read at 50; the crown moved its place at 300.
        service.receivePosition(.init(bookId: book.id, bookTitle: book.title, wordIndex: 5,
            timestamp: Date(timeIntervalSince1970: 50), furthestReadWordIndex: 5,
            browseWordIndex: 64, browseTimestamp: Date(timeIntervalSince1970: 300)))
        #expect(book.browseWordIndex == 64)
        #expect(book.browseDate == Date(timeIntervalSince1970: 300))
        #expect(book.lastReadWordIndex == 20)
        #expect(book.lastReadDate == Date(timeIntervalSince1970: 100))
    }

    @Test func anOlderPlaceDeliveredLateDoesNotUndoANewerOne() throws {
        let (service, container, book) = try positionFixture()
        service.receivePosition(position(book, index: 80, time: 300))
        service.receivePosition(position(book, index: 60, time: 200))
        #expect(book.lastReadWordIndex == 80)
        #expect(book.browseWordIndex == 80)
        #expect(book.furthestReadWordIndex == 80)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test(arguments: [-100, 1000])
    func anAdoptedPlaceIsClampedOnBothSides(index: Int) throws {
        // Direct callers are not protected by the transport decoder.
        let (service, container, book) = try positionFixture()
        service.receivePosition(position(book, index: index, time: 200))
        let expected = index < 0 ? 0 : 99
        #expect(book.lastReadWordIndex == expected)
        #expect(book.browseWordIndex == expected)
        #expect(book.furthestReadWordIndex == (index < 0 ? 20 : 99))
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first)
        #expect(saved.browseWordIndex == expected)
    }

    @Test func unconfiguredAndUnknownBookPositionsChangeNothing() throws {
        let (service, container, book) = try positionFixture()
        let unconfigured = WatchSyncService(session: FakeWatchConnectivitySession())
        unconfigured.receivePosition(position(book, index: 70, time: 200))
        service.receivePosition(.init(bookId: UUID(), bookTitle: "Unknown", wordIndex: 70,
                                      timestamp: Date(timeIntervalSince1970: 200), furthestReadWordIndex: 90))
        #expect(book.lastReadWordIndex == 20)
        #expect(book.furthestReadWordIndex == 20)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    // MARK: - Presence

    @Test func aFreshPlayingPayloadRaisesPresenceAndAPauseClearsIt() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 201) }
        service.receivePosition(live(book, index: 40, sentAt: 200, startedAt: 190))
        #expect(service.remotePresence(for: book.id)?.wordIndex == 40)
        #expect(book.browseWordIndex == 40)

        service.receivePosition(position(book, index: 44, time: 202, sentAt: 202))
        #expect(service.remotePresence == nil)
        #expect(book.browseWordIndex == 44)
    }

    @Test func aPauseOlderThanTheLiveHeartbeatDoesNotClearIt() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 201) }
        service.receivePosition(live(book, index: 40, sentAt: 200, startedAt: 190))
        service.receivePosition(position(book, index: 30, time: 150, sentAt: 150))
        #expect(service.remotePresence?.wordIndex == 40)
        #expect(book.browseWordIndex == 40)
    }

    @Test func presenceExpiresWhenTheReadingDeviceGoesQuiet() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 200) }
        service.receivePosition(live(book, index: 40, sentAt: 200, startedAt: 190))
        service.expirePresence(now: Date(timeIntervalSince1970: 205.9))
        #expect(service.remotePresence != nil)
        service.expirePresence(now: Date(timeIntervalSince1970: 206))
        #expect(service.remotePresence == nil)
        // Unlocked at the last place heard.
        #expect(book.browseWordIndex == 40)
    }

    @Test func aPlayingContextDeliveredLateRaisesNoCard() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 900) }
        service.receivePosition(live(book, index: 40, sentAt: 200, startedAt: 190))
        #expect(service.remotePresence == nil)
        #expect(book.browseWordIndex == 40)
    }

    @Test func presenceIsNotShownForTheBookThisDeviceIsReading() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 200) }
        service.receivePosition(live(book, index: 40, sentAt: 200, startedAt: 190))
        #expect(service.remotePresence(for: UUID()) == nil)
        #expect(service.remotePresence(for: nil) == nil)
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { _ in })
        #expect(service.remotePresence == nil)
        #expect(service.localRunBookId == book.id)
        service.endLocalRun(bookId: book.id)
        #expect(service.localRunBookId == nil)
    }

    // MARK: - Yield

    @Test func aLaterRunOnTheWatchMakesThePhoneYieldAtItsWord() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 200) }
        var yielded: RemotePresence?
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { yielded = $0 })

        service.clock = { Date(timeIntervalSince1970: 210) }
        service.receivePosition(live(book, index: 66, sentAt: 210, startedAt: 205))

        #expect(yielded?.wordIndex == 66)
        #expect(service.localRunBookId == nil)
        #expect(service.remotePresence(for: book.id)?.wordIndex == 66)
        #expect(book.browseWordIndex == 66)
    }

    @Test func anOlderRunOnTheWatchIsIgnoredAndCannotMoveThePhone() throws {
        let (service, container, book) = try positionFixture()
        defer { withExtendedLifetime(container) {} }
        service.clock = { Date(timeIntervalSince1970: 200) }
        var yielded = false
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { _ in yielded = true })

        service.receivePosition(live(book, index: 66, sentAt: 200, startedAt: 150))

        #expect(!yielded)
        #expect(service.localRunBookId == book.id)
        #expect(service.remotePresence(for: book.id) == nil)
        #expect(book.browseWordIndex == 20)
        #expect(book.lastReadWordIndex == 20)
        service.endLocalRun(bookId: book.id)
    }

    // MARK: - Sending

    @Test func aCommitGoesLiveWhenReachableAndAlwaysByContext() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        service.syncReadingPosition(bookId: UUID(), bookTitle: "B", wordIndex: 3)
        #expect(connection.applicationContexts.count == 1)
        #expect(connection.messages.isEmpty)
        connection.isReachable = true
        service.syncReadingPosition(bookId: UUID(), bookTitle: "B", wordIndex: 4)
        #expect(connection.applicationContexts.count == 2)
        #expect(connection.messages.count == 1)
    }

    @Test func heartbeatsAreLiveOnlyAndCarryTheRun() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        service.heartbeatInterval = .seconds(3_600)
        service.clock = { Date(timeIntervalSince1970: 500) }
        let id = UUID()
        let snapshot = WatchSyncLogic.PositionPayload(bookId: id, bookTitle: "B", wordIndex: 1,
            timestamp: Date(timeIntervalSince1970: 400)).movingPlace(to: 12, at: Date(timeIntervalSince1970: 500))
        service.beginLocalRun(bookId: id, snapshot: { snapshot }, onYield: { _ in })

        service.sendHeartbeat()
        #expect(connection.messages.isEmpty)

        connection.isReachable = true
        service.sendHeartbeat()
        let sent = try #require(connection.messages.last.flatMap { WatchSyncLogic.PositionPayload.decode(from: $0) })
        #expect(sent.isPlaying)
        #expect(sent.playStartedAt == Date(timeIntervalSince1970: 500))
        #expect(sent.browseWordIndex == 12)
        #expect(sent.sentAt == Date(timeIntervalSince1970: 500))
        #expect(connection.applicationContexts.isEmpty)

        service.endLocalRun(bookId: id)
        let heartbeats = connection.messages.count
        service.sendHeartbeat()
        #expect(connection.messages.count == heartbeats)
        service.syncReadingPosition(bookId: id, bookTitle: "B", wordIndex: 13)
        let release = try #require(connection.applicationContexts.last.flatMap { WatchSyncLogic.PositionPayload.decode(from: $0) })
        #expect(!release.isPlaying)
        #expect(release.playStartedAt == nil)
    }

    @Test func browseMovesAreCoalescedToTheLatest() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        service.placeCoalescing = .seconds(3_600)
        let id = UUID()
        func place(_ index: Int) -> WatchSyncLogic.PositionPayload {
            .init(bookId: id, bookTitle: "B", wordIndex: 0, timestamp: Date(timeIntervalSince1970: 1),
                  browseWordIndex: index, browseTimestamp: Date(timeIntervalSince1970: Double(index)))
        }
        service.publishPlace(place(1))
        service.publishPlace(place(2))
        service.publishPlace(place(3))
        #expect(connection.applicationContexts.isEmpty)
        service.flushPendingPlace()
        #expect(connection.applicationContexts.count == 1)
        #expect(connection.applicationContexts.last.flatMap { WatchSyncLogic.PositionPayload.decode(from: $0) }?.browseWordIndex == 3)
        service.flushPendingPlace()
        #expect(connection.applicationContexts.count == 1)
    }

    @Test func aCommitSupersedesAQueuedBrowseMove() throws {
        let connection = FakeWatchConnectivitySession()
        connection.activationState = .activated
        let service = WatchSyncService(session: connection)
        service.placeCoalescing = .seconds(3_600)
        let id = UUID()
        service.publishPlace(.init(bookId: id, bookTitle: "B", wordIndex: 0, timestamp: Date(timeIntervalSince1970: 1),
                                   browseWordIndex: 9, browseTimestamp: Date(timeIntervalSince1970: 1)))
        service.syncReadingPosition(bookId: id, bookTitle: "B", wordIndex: 30)
        service.flushPendingPlace()
        #expect(connection.applicationContexts.count == 1)
        #expect(connection.applicationContexts.last.flatMap { WatchSyncLogic.PositionPayload.decode(from: $0) }?.browseWordIndex == 30)
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

    private func position(_ book: Book, index: Int, time: Double, furthest: Int? = nil,
                          sentAt: Double? = nil) -> WatchSyncLogic.PositionPayload {
        .init(bookId: book.id, bookTitle: book.title, wordIndex: index,
              timestamp: Date(timeIntervalSince1970: time), furthestReadWordIndex: furthest ?? index,
              sentAt: sentAt.map { Date(timeIntervalSince1970: $0) })
    }

    /// A heartbeat from the watch: playing, its place moved at `sentAt`, reading stamp old.
    private func live(_ book: Book, index: Int, sentAt: Double, startedAt: Double) -> WatchSyncLogic.PositionPayload {
        .init(bookId: book.id, bookTitle: book.title, wordIndex: 0,
              timestamp: Date(timeIntervalSince1970: 1), furthestReadWordIndex: 0,
              browseWordIndex: index, browseTimestamp: Date(timeIntervalSince1970: sentAt),
              isPlaying: true, playStartedAt: Date(timeIntervalSince1970: startedAt),
              sentAt: Date(timeIntervalSince1970: sentAt))
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
