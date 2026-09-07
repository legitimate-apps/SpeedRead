import Foundation
import Testing
import WatchConnectivity
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
import SwiftData
@testable import SpeedRead
#endif

@Suite("Completion wire journeys")
@MainActor
struct CompletionWireJourneyTests {
    @Test func finishingRoundTripPreservesOriginalDateAndBothProgressValues() async throws {
        // Mutations: drop completion/date in either sender or receiver, replace the original
        // date on re-finish, or leave receiver progress at index/count after accepting a finish.
        let origin = try CompletionPeer()
        let remote = try CompletionPeer()
        let originalDate = Date(timeIntervalSince1970: 100)
        origin.commit(index: 99, didFinish: true, time: 100)
        let outbound = try origin.lastContext()
        #expect(outbound["didFinish"] as? Bool == true)
        #expect(outbound["finishedAt"] as? Double == 100)
        try await remote.receive(outbound)
        #expect(origin.progress == 1)
        #expect(remote.progress == origin.progress)
        #expect(remote.finishedAt == originalDate)
        #expect(try remote.persistedFinishedAt() == originalDate)

        // A reread on the origin ensures the returning finish must actually be accepted.
        origin.commit(index: 0, didFinish: false, time: 150)
        remote.commit(index: 99, didFinish: true, time: 200)
        #expect(remote.finishedAt == originalDate)
        try await origin.receive(remote.lastContext())
        #expect(origin.finishedAt == originalDate)
        #expect(try origin.persistedFinishedAt() == originalDate)
        origin.commit(index: 99, didFinish: true, time: 300)
        #expect(origin.finishedAt == originalDate)
        #expect(origin.progress == 1)
        #expect(remote.progress == origin.progress)
        #if os(iOS)
        #expect(ReaderView.readingEstimate(book: origin.book, lastWPM: 250) == "100% · finished")
        #else
        let book = try #require(origin.service.currentBook)
        #expect(WatchLibraryPresentation.progressText(for: book) == "100% complete")
        #endif
    }

    @Test(arguments: [0, 99])
    func nonfinishingCommitClearsLocalAndRemoteCompletion(index: Int) async throws {
        // Mutations: retain completion on a non-finishing final-word commit, keep completion
        // monotonic at the receiver, or suppress a same-index completion-change offer on iOS.
        let origin = try CompletionPeer()
        let remote = try CompletionPeer()
        origin.commit(index: 99, didFinish: true, time: 100)
        try await remote.receive(origin.lastContext())
        origin.commit(index: index, didFinish: false, time: 200)
        #expect(origin.finishedAt == nil)
        let outgoing = try origin.lastContext()
        #expect(outgoing["didFinish"] as? Bool == false)
        #expect(outgoing["finishedAt"] == nil)
        try await remote.receive(outgoing)
        #expect(remote.finishedAt == nil)
        #expect(try remote.persistedFinishedAt() == nil)
        #expect(remote.progress == Double(index) / 100)
        #expect(remote.progress == origin.progress)
    }

    @Test func oldFormatCommitClearsCompletionEvenWithAnUnrelatedDateKey() async throws {
        // Mutations: default absent didFinish to true, infer completion from a date or final
        // index, or reject a compatible old context instead of applying its non-finish.
        let peer = try CompletionPeer()
        peer.commit(index: 99, didFinish: true, time: 100)
        var legacy = try peer.lastContext()
        legacy.removeValue(forKey: "didFinish")
        legacy.removeValue(forKey: "finishedAt")
        legacy["timestamp"] = 200.0
        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: legacy))
        #expect(!decoded.didFinish)
        #expect(decoded.finishedAt == nil)
        try await peer.receive(legacy)
        #expect(peer.finishedAt == nil)
        #expect(peer.progress == 0.99)
        legacy["finishedAt"] = 100.0
        let dateAlone = try #require(WatchSyncLogic.PositionPayload.decode(from: legacy))
        #expect(!dateAlone.didFinish)
        #expect(dateAlone.finishedAt == nil)
    }
}

@MainActor
private final class CompletionPeer {
    static let id = UUID(uuidString: "B173C05E-2090-4442-8F6B-88E703BB0099")!
    let connection = CompletionConnection()
    let service: WatchSyncService
    #if os(watchOS)
    let storage: WatchTestStorage
    #else
    let container: ModelContainer
    let book: Book
    #endif

    init() throws {
        let text = (0..<100).map { "word\($0)" }.joined(separator: " ")
        #if os(watchOS)
        storage = try WatchTestStorage()
        service = WatchSyncService(session: connection, store: storage.store)
        let book = WatchBook(id: Self.id, title: "Completion", author: "", text: text,
            lastReadIndex: 0, lastReadDate: nil, wordCount: 100, dateAdded: .distantPast)
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        #else
        container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        book = Book(title: "Completion", author: "", extractedText: text, sourceFileName: "completion.txt")
        book.id = Self.id
        container.mainContext.insert(book)
        try container.mainContext.save()
        service = WatchSyncService(session: connection)
        service.configure(modelContext: container.mainContext)
        #endif
    }

    var finishedAt: Date? {
        #if os(watchOS)
        service.currentBook?.finishedAt
        #else
        book.finishedAt
        #endif
    }

    var progress: Double {
        #if os(watchOS)
        service.currentBook?.progress ?? -1
        #else
        book.progress
        #endif
    }

    func persistedFinishedAt() throws -> Date? {
        #if os(watchOS)
        return try #require(storage.store.load().currentBook).finishedAt
        #else
        return try #require(ModelContext(container).fetch(FetchDescriptor<Book>()).first).finishedAt
        #endif
    }

    func commit(index: Int, didFinish: Bool, time: Double) {
        let now = Date(timeIntervalSince1970: time)
        #if os(watchOS)
        service.syncReadingPosition(bookId: Self.id, bookTitle: "Completion", wordIndex: index,
                                    timestamp: now, didFinish: didFinish)
        #else
        _ = ReadingPositionCoordinator.commit(index, wordCount: book.wordCount, book: book,
            saver: container.mainContext, sync: service, now: now, didFinish: didFinish)
        #endif
    }

    func lastContext() throws -> [String: Any] {
        let dictionary = try #require(connection.contexts.last)
        // Cross the same property-list boundary WCSession requires, not just a typed payload.
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func receive(_ dictionary: [String: Any]) async throws {
        let payload = try #require(WatchSyncLogic.PositionPayload.decode(from: dictionary))
        service.session(.default, didReceiveApplicationContext: dictionary)
        #if os(watchOS)
        for _ in 0..<100 where service.currentBook?.lastReadDate != payload.timestamp { await Task.yield() }
        #expect(service.currentBook?.lastReadDate == payload.timestamp)
        #else
        for _ in 0..<100 where service.pendingWatchPositionOffer == nil { await Task.yield() }
        let offer = try #require(service.pendingWatchPositionOffer)
        #expect(offer.timestamp == payload.timestamp)
        if payload.didFinish { #expect(offer.displayText.contains("100%")) }
        #expect(service.continueFromWatch(offer))
        #expect(book.lastReadDate == payload.timestamp)
        #endif
    }
}

@MainActor
private final class CompletionConnection: WatchConnectivitySession {
    struct Transfer {}
    var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .activated
    var isReachable = false
    #if os(iOS)
    var isPaired = true
    #endif
    var contexts: [[String: Any]] = []
    func activate() {}
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((any Error) -> Void)?) {}
    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer { Transfer() }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws { contexts.append(applicationContext) }
}
