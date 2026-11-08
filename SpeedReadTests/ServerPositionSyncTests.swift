import Foundation
import SwiftData
import Testing
import UIKit
@testable import SpeedRead

/// The service end to end against a scripted server: what is pushed, when, and what a pulled
/// position turns into on this device.
@Suite("Server position sync", .serialized)
@MainActor
struct ServerPositionSyncTests {
    @Test func aCommittedPositionIsPushedWithItsAnchor() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.script.enqueue(f.pushURL, data: Data(#"{"document":"d1g35t","timestamp":1790000000}"#.utf8))
        f.readBackOwnPosition()

        _ = ReadingPositionCoordinator.commit(120, wordCount: f.book.wordCount, book: f.book,
                                              saver: f.context, sync: RecordingSync(), serverSync: f.sync)
        await f.sync.flush()

        let push = try f.pushedBody(at: 1)
        #expect(push["document"] as? String == "d1g35t")
        #expect(push["percentage"] as? Double == 0.4)
        #expect(push["device_id"] as? String == f.sync.deviceID)
        #expect(push["device"] as? String == "SpeedRead (Test)")
        #expect(push["position_kind"] as? String == "percentage")
        #expect(push["progress"] == nil)
        let anchor = try #require(push["anchor"] as? [String: String])
        #expect(anchor == ["text": "w120", "before": "w112 w113 w114 w115 w116 w117 w118 w119",
                           "after": "w121 w122 w123 w124 w125 w126 w127 w128"])
    }

    @Test func aFinishedBookPushesOneHundredPercentWithNoAnchor() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.pushAccepted()

        _ = ReadingPositionCoordinator.commit(299, wordCount: f.book.wordCount, book: f.book, saver: f.context,
                                              sync: RecordingSync(), serverSync: f.sync, didFinish: true)
        await f.sync.flush()

        let push = try f.pushedBody(at: 1)
        #expect(push["percentage"] as? Double == 1)
        #expect(push["anchor"] == nil)
    }

    @Test func aBookWithoutADigestIsPushedUnderTheServersBookID() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.book.sourceDigest = nil
        f.supportsAnchors()
        f.pushAccepted(document: "42")

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(try f.pushedBody(at: 1)["document"] as? String == "42")
    }

    @Test func nothingIsSentWhenTheServersSyncIsOff() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.server.syncsReadingPosition = false

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.script.observed.isEmpty)
    }

    @Test func nothingIsSentForABookFromSomewhereElse() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.book.origin = nil

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        await f.sync.pull(bookId: f.book.id)

        #expect(f.script.observed.isEmpty)
    }

    @Test func aStockServerIsProbedOnceAndNeverWrittenTo() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: 401)

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL])
    }

    /// CWNG answers a wrong password with 401. Nothing is written, as for a stock server, but the
    /// reader is told it is the password, and saving the server asks again.
    @Test func aRefusedPasswordIsNamedUntilTheServerIsSaved() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: 401)
        #expect(f.sync.problem(for: f.server.id) == nil)

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.sync.problem(for: f.server.id) == .credentialsRefused)
        #expect(f.sync.problem(for: f.server.id)?.message.contains("password") == true)
        #expect(f.script.observed.map(\.url) == [f.authURL])
        f.sync.serverSettingsChanged(f.server)
        #expect(f.sync.problem(for: f.server.id) == nil)
    }

    @Test func aStockServerIsNotAProblem() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: 404)
        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        #expect(f.sync.problem(for: f.server.id) == nil)
    }

    /// A device removed in CWNG gets 409 `device_inactive` on every push. It is not retried and
    /// not queued again, and the reader is told in the server's words.
    @Test func aRemovedDeviceStopsPushingAndSaysSo() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        let body = #"{"error":"device_inactive","message":"This device was removed from the account, so it no longer syncs"}"#
        f.script.enqueue(f.pushURL, data: Data(body.utf8), status: 409)

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        await f.sync.flush()
        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.pushURL])
        let problem = try #require(f.sync.problem(for: f.server.id))
        #expect(problem == .deviceRemoved("This device was removed from the account, so it no longer syncs"))
        #expect(problem.message.hasPrefix("This device was removed from the account, so it no longer syncs."))
        #expect(f.script.remaining == 0)
    }

    @Test func aFailedPushIsSentAgainAtTheNextFlush() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.script.enqueue(f.pushURL, status: 503)
        f.pushAccepted()

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.pushURL, f.pushURL, f.fetchURL])
        #expect(f.script.remaining == 0)
    }

    @Test func rapidCommitsBecomeOnePushAfterTheQuietInterval() async throws {
        let f = try Fixture(pushDelay: .milliseconds(100))
        defer { f.close() }
        f.supportsAnchors()
        f.pushAccepted()

        for index in [10, 20, 30] {
            _ = ReadingPositionCoordinator.commit(index, wordCount: f.book.wordCount, book: f.book,
                                                  saver: f.context, sync: RecordingSync(), serverSync: f.sync)
        }
        #expect(f.script.observed.isEmpty)
        let deadline = ContinuousClock.now + .seconds(5)
        while f.script.observed.count < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(f.script.observed.map(\.url) == [f.authURL, f.pushURL, f.fetchURL])
        #expect(try f.pushedBody(at: 1)["percentage"] as? Double == 0.1)
    }

    @Test func aSecondFlushWaitsForTheOneOnTheWire() async throws {
        // Two pushes in flight could land out of order, and the server lets a device rewind its
        // own position — so the older one arriving last would move the server backwards.
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.script.enqueue(f.pushURL, held: true)
        f.readBackOwnPosition()
        f.pushAccepted()
        _ = ReadingPositionCoordinator.commit(30, wordCount: f.book.wordCount, book: f.book,
                                              saver: f.context, sync: RecordingSync(), serverSync: f.sync)
        let first = Task { await f.sync.flush() }
        let deadline = ContinuousClock.now + .seconds(5)
        while f.script.observed.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = ReadingPositionCoordinator.commit(60, wordCount: f.book.wordCount, book: f.book,
                                              saver: f.context, sync: RecordingSync(), serverSync: f.sync)
        let second = Task { await f.sync.flush() }
        try await Task.sleep(for: .milliseconds(200))

        #expect(f.script.observed.count == 2, "the second push must not start while the first is unanswered")

        f.script.release()
        await first.value
        await second.value
        #expect(f.script.observed.map(\.url) == [f.authURL, f.pushURL, f.fetchURL, f.pushURL, f.fetchURL])
        #expect(try f.pushedBody(at: 1)["percentage"] as? Double == 0.1)
        #expect(try f.pushedBody(at: 3)["percentage"] as? Double == 0.2)
    }

    @Test func theServiceKeepsItsContainerAlive() async throws {
        // A context does not retain its container; fetching through one whose container was
        // released traps inside SwiftData. Observed in the hosted lane, where a rendering test
        // configured the shared service with a container it then released.
        let script = MockRequestScript()
        let defaults = IsolatedDefaults()
        let sync = ServerPositionSync(client: KOSyncClient(session: mockSession(script: script)),
                                      defaults: defaults.defaults, deviceName: "x")
        let bookID: UUID, tag: String, position: String
        do {
            let scoped = try Fixture.makeContents()
            sync.configure(modelContainer: scoped.container)
            bookID = scoped.book.id
            tag = scoped.server.keychainTag
            position = Fixture.position(in: scoped.book.extractedText, at: 210, percentage: 0.69)
        }
        defer {
            script.close()
            try? KeychainStore.deletePassword(for: tag)
        }
        script.enqueue(Fixture.authURL, data: Fixture.capableAuthBody)
        script.enqueue(Fixture.fetchURL(document: "d1g35t"), data: Data(position.utf8))

        await sync.pull(bookId: bookID)

        // Only a live container can have found the book, its server and the place in its text.
        #expect(sync.pendingOffer?.index == 210)
    }

    @Test func aProbeThatGetsNoAnswerIsAskedAgainAndThePushKept() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.script.fail(f.authURL)
        f.supportsAnchors()
        f.pushAccepted()

        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()
        #expect(f.script.observed.map(\.url) == [f.authURL])
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.authURL, f.pushURL, f.fetchURL])
        #expect(f.script.remaining == 0)
    }

    @Test func savingTheServerAsksItAgain() async throws {
        // A refusal may have been a wrong password; the corrected one must not wait for a relaunch.
        let f = try Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: 401)
        f.supportsAnchors()
        f.pushAccepted()
        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        let edit = ServerEditSession()
        edit.loadExisting(server: f.server)
        #expect(edit.save(server: f.server, modelContext: f.context, positionSync: f.sync))
        f.sync.noteCommitted(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.authURL, f.pushURL, f.fetchURL])
    }

    @Test func turningSyncOffStopsAPushAlreadyUnderWay() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, data: Fixture.capableAuthBody, held: true)
        f.sync.noteCommitted(bookId: f.book.id)
        let flush = Task { await f.sync.flush() }
        try await f.waitForRequests(1)

        f.server.syncsReadingPosition = false
        f.script.release()
        await flush.value

        #expect(f.script.observed.map(\.url) == [f.authURL])
    }

    @Test func aPushThatLosesReadsTheWinnerBack() async throws {
        // Furthest wins on the server, and a losing push still gets a 200.
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.script.enqueue(f.pushURL)
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69, seconds: f.inAMinute))
        _ = ReadingPositionCoordinator.commit(30, wordCount: f.book.wordCount, book: f.book,
                                              saver: f.context, sync: RecordingSync(), serverSync: f.sync)

        await f.sync.flush()

        #expect(f.sync.pendingOffer?.index == 210)
    }

    @Test func backgroundTimeEndsOnceWhenTheFlushFinishes() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.pushAccepted()
        let tasks = FakeBackgroundTasks()
        f.sync.noteCommitted(bookId: f.book.id)

        await f.sync.flushInBackground(application: tasks).value

        #expect(tasks.names == ["position-sync"])
        #expect(tasks.ended == [FakeBackgroundTasks.identifier])
        #expect(f.script.observed.map(\.url) == [f.authURL, f.pushURL, f.fetchURL])
    }

    @Test func backgroundTimeEndsOnceWhenItExpiresFirst() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.script.enqueue(f.pushURL, held: true)
        f.readBackOwnPosition()
        let tasks = FakeBackgroundTasks()
        f.sync.noteCommitted(bookId: f.book.id)

        let background = f.sync.flushInBackground(application: tasks)
        try await f.waitForRequests(2)
        tasks.expire()
        #expect(tasks.ended == [FakeBackgroundTasks.identifier], "iOS's deadline ends it, not the request")

        f.script.release()
        await background.value
        #expect(tasks.ended == [FakeBackgroundTasks.identifier], "the late flush must not end it twice")
    }

    // MARK: Pull

    @Test func aNewerPlaceFromAnotherReaderBecomesAnOfferAtItsAnchor() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))

        await f.sync.pull(bookId: f.book.id)

        let offer = try #require(f.sync.pendingOffer)
        #expect(offer.bookId == f.book.id)
        #expect(offer.index == 210)
        #expect(offer.finished == false)
        // The server says 69% of its copy; the anchor lands at word 210 of 300 in this one, and the
        // banner names the place the reader will see after Continue.
        #expect(offer.displayText == "Continue from Kobo Libra 2 — 70%")
        #expect(offer.snippet == "…w206 w207 w208 w209 w210 w211 w212 w213 w214…")
        #expect(f.book.lastReadWordIndex == 0, "a pull never moves the reader by itself")
    }

    @Test func aMissByDigestIsLookedUpByTheServersBookID() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", body: "{}")
        f.serve(document: "42", position: f.koboPosition(at: 150, percentage: 0.5))

        await f.sync.pull(bookId: f.book.id)

        #expect(f.sync.pendingOffer?.index == 150)
    }

    @Test func acceptingMovesTheReaderAndDoesNotEchoBack() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        await f.sync.pull(bookId: f.book.id)
        let offer = try #require(f.sync.pendingOffer)
        let watch = RecordingSync()

        #expect(f.sync.accept(offer, sync: watch))
        await f.sync.flush()

        #expect(f.book.lastReadWordIndex == 210)
        #expect(f.book.furthestReadWordIndex == 210)
        #expect(f.book.browseWordIndex == 210)
        #expect(watch.indices == [210], "the watch follows an accepted place")
        #expect(f.sync.pendingOffer == nil)
        #expect(f.script.observed.count == 2, "no push of the server's own position")
    }

    @Test func readingHereWithdrawsTheOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer != nil)

        f.sync.noteCommitted(bookId: f.book.id)

        #expect(f.sync.pendingOffer == nil)
    }

    @Test func aPullThatFindsNothingNewWithdrawsTheOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69, device: f.sync.deviceID))
        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer != nil)

        await f.sync.pull(bookId: f.book.id)

        #expect(f.sync.pendingOffer == nil)
    }

    @Test func aLateAnswerCannotBringBackADismissedOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69), held: true)
        let pull = Task { await f.sync.pull(bookId: f.book.id) }
        try await f.waitForRequests(2)

        f.sync.dismissOffer(for: f.book.id)
        f.script.release()
        await pull.value

        #expect(f.sync.pendingOffer == nil)
    }

    @Test func anOlderAnswerDoesNotReplaceANewerOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 240, percentage: 0.8, seconds: 1_790_000_000),
                held: true)
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69, seconds: 1_790_000_100))
        let older = Task { await f.sync.pull(bookId: f.book.id) }
        try await f.waitForRequests(2)
        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer?.index == 210)

        f.script.release()
        await older.value

        #expect(f.sync.pendingOffer?.index == 210)
    }

    @Test func acceptingDropsAPushQueuedBeforeIt() async throws {
        // The queued push holds the place the reader just chose to leave.
        let f = try Fixture()
        defer { f.close() }
        _ = ReadingPositionCoordinator.commit(30, wordCount: f.book.wordCount, book: f.book,
                                              saver: f.context, sync: RecordingSync(), serverSync: f.sync)
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69, seconds: f.inAMinute))
        await f.sync.pull(bookId: f.book.id)
        let offer = try #require(f.sync.pendingOffer)

        #expect(f.sync.accept(offer, sync: RecordingSync()))
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL])
        #expect(f.book.lastReadWordIndex == 210)
    }

    @Test func anOfferThatWasWithdrawnCannotBeAccepted() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        await f.sync.pull(bookId: f.book.id)
        let offer = try #require(f.sync.pendingOffer)
        f.sync.dismissOffer(for: f.book.id)

        #expect(!f.sync.accept(offer))
        #expect(f.book.lastReadWordIndex == 0)
    }

    @Test func turningSyncOffWithdrawsItsOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer != nil)

        let edit = ServerEditSession()
        edit.loadExisting(server: f.server)
        edit.syncsReadingPosition = false
        #expect(edit.save(server: f.server, modelContext: f.context, positionSync: f.sync))

        #expect(f.sync.pendingOffer == nil)
    }

    @Test func aDeclinedOfferIsNotMadeAgainForTheSameServerPosition() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69))
        f.serve(document: "d1g35t", position: f.koboPosition(at: 240, percentage: 0.8, seconds: 1_790_000_100))
        await f.sync.pull(bookId: f.book.id)
        f.sync.decline(try #require(f.sync.pendingOffer))

        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer == nil)
        #expect(f.book.lastReadWordIndex == 0)

        await f.sync.pull(bookId: f.book.id)
        #expect(f.sync.pendingOffer?.index == 240, "the server moved on, so it is news again")
    }

    @Test func ourOwnPositionComingBackIsNotAnOffer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnchors()
        f.serve(document: "d1g35t", position: f.koboPosition(at: 210, percentage: 0.69, device: f.sync.deviceID))

        await f.sync.pull(bookId: f.book.id)

        #expect(f.sync.pendingOffer == nil)
    }

    @Test func theDeviceIDIsStableAcrossLaunches() throws {
        let defaults = IsolatedDefaults()
        let first = ServerPositionSync(defaults: defaults.defaults, deviceName: "x")
        let second = ServerPositionSync(defaults: defaults.defaults, deviceName: "x")
        #expect(first.deviceID == second.deviceID)
        #expect(UUID(uuidString: first.deviceID) != nil)
    }

    // MARK: Fixture

    private final class RecordingSync: ReadingPositionSyncing {
        private(set) var indices: [Int] = []
        func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int, timestamp: Date,
                                 furthestReadWordIndex: Int, didFinish: Bool, finishedAt: Date?) {
            indices.append(wordIndex)
        }
    }

    @MainActor
    private final class FakeBackgroundTasks: BackgroundTasking {
        static let identifier = UIBackgroundTaskIdentifier(rawValue: 7)
        private(set) var names: [String] = []
        private(set) var ended: [UIBackgroundTaskIdentifier] = []
        private var expiration: (@MainActor @Sendable () -> Void)?

        func beginBackgroundTask(withName taskName: String?,
                                 expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
            names.append(taskName ?? "")
            expiration = handler
            return Self.identifier
        }

        func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) { ended.append(identifier) }

        func expire() { expiration?() }
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let script = MockRequestScript()
        let defaults = IsolatedDefaults()
        let sync: ServerPositionSync
        let server: OPDSServer
        let book: Book
        static let authURL = URL(string: "https://books.example.com/kosync/users/auth")!
        static let capableAuthBody = Data(#"{"authorized":"OK","capabilities":["position_kinds","percentage_push","anchor","book_id_document"]}"#.utf8)
        let authURL = Fixture.authURL
        let pushURL = URL(string: "https://books.example.com/kosync/syncs/progress")!
        let fetchURL = Fixture.fetchURL(document: "d1g35t")
        /// A server receipt time after anything this test commits.
        let inAMinute = Int(Date().timeIntervalSince1970) + 60

        init(pushDelay: Duration = .seconds(60)) throws {
            (container, server, book) = try Self.makeContents()
            context = container.mainContext
            sync = ServerPositionSync(client: KOSyncClient(session: mockSession(script: script)),
                                      defaults: defaults.defaults, deviceName: "SpeedRead (Test)", pushDelay: pushDelay)
            sync.configure(modelContainer: container)
        }

        /// A 300-word book "w0 … w299" downloaded from a server that syncs positions.
        static func makeContents() throws -> (container: ModelContainer, server: OPDSServer, book: Book) {
            let container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let server = OPDSServer(name: "Library", baseURL: URL(string: "https://books.example.com/opds")!,
                                    username: "reader")
            try KeychainStore.setPassword("hunter2", for: server.keychainTag)
            let book = Book(title: "Words", author: "A",
                            extractedText: (0..<300).map { "w\($0)" }.joined(separator: " "), sourceFileName: "words.epub")
            book.sourceDigest = "d1g35t"
            book.origin = BookOrigin(serverID: server.id, entryID: "urn:uuid:1", serverBookID: "42")
            container.mainContext.insert(server)
            container.mainContext.insert(book)
            try container.mainContext.save()
            return (container, server, book)
        }

        static func fetchURL(document: String) -> URL {
            KOSyncWire.fetchURL(base: URL(string: "https://books.example.com/kosync")!, document: document)!
        }

        func supportsAnchors() {
            script.enqueue(authURL, data: Self.capableAuthBody)
        }

        /// A push the server takes, and the read-back after it finding this device's own place.
        func pushAccepted(document: String = "d1g35t") {
            script.enqueue(pushURL)
            readBackOwnPosition(document: document)
        }

        func readBackOwnPosition(document: String = "d1g35t") {
            serve(document: document, body: #"{"percentage":0.1,"device":"SpeedRead (Test)","device_id":"\#(sync.deviceID)","timestamp":\#(inAMinute)}"#)
        }

        func serve(document: String, body: String, held: Bool = false) {
            script.enqueue(Self.fetchURL(document: document), data: Data(body.utf8), held: held)
        }

        func serve(document: String, position: String, held: Bool = false) {
            serve(document: document, body: position, held: held)
        }

        /// A position another reader set, anchored at word `index` of this book.
        func koboPosition(at index: Int, percentage: Double, device: String = "KOBO-1",
                          seconds: Int = 1_790_000_000) -> String {
            Self.position(in: book.extractedText, at: index, percentage: percentage, device: device, seconds: seconds)
        }

        static func position(in text: String, at index: Int, percentage: Double, device: String = "KOBO-1",
                             seconds: Int = 1_790_000_000) -> String {
            let anchor = ReadingAnchor.build(text: text, tokenIndex: index)!
            return #"{"percentage":\#(percentage),"position_kind":"locator","device":"Kobo Libra 2","device_id":"\#(device)","timestamp":\#(seconds),"anchor":{"text":"\#(anchor.text)","before":"\#(anchor.before)","after":"\#(anchor.after)"}}"#
        }

        func waitForRequests(_ count: Int) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while script.observed.count < count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(script.observed.count >= count)
        }

        func pushedBody(at position: Int) throws -> [String: Any] {
            let request = try #require(script.observed.dropFirst(position).first)
            #expect(request.httpMethod == "PUT")
            let body = try #require(request.httpBody ?? request.bodyStreamData)
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }

        func close() {
            script.close()
            try? KeychainStore.deletePassword(for: server.keychainTag)
        }
    }
}
