import Foundation
import SwiftUI
import Testing
import WatchConnectivity
@testable import SpeedReadWatch_Watch_App

@Suite("Watch live handoff")
@MainActor
struct WatchLiveHandoffTests {
    private let storage: WatchTestStorage

    init() throws {
        storage = try WatchTestStorage()
    }

    // MARK: - The phone's place is the watch's place

    @Test func aNewerPhonePlaceIsAdoptedAndPersisted() throws {
        let (service, book) = fixture()
        service.receivePosition(phone(book, reading: 4, at: 200))
        let stored = try #require(service.currentBook)
        #expect(stored.lastReadIndex == 4)
        #expect(stored.browseWordIndex == 4)
        #expect(stored.browseDate == Date(timeIntervalSince1970: 200))
        #expect(storage.store.load().currentBook?.browseWordIndex == 4)
    }

    @Test func aScrubOnThePhoneMovesTheWatchWordButNotTheReadingPosition() throws {
        let (service, book) = fixture()
        service.receivePosition(phone(book, reading: 1, at: 50, place: 7, placedAt: 300))
        let stored = try #require(service.currentBook)
        #expect(stored.browseWordIndex == 7)
        #expect(stored.lastReadIndex == 2)
        #expect(stored.lastReadDate == Date(timeIntervalSince1970: 100))
    }

    @Test func aPlaceNeverMovedDatesFromTheLastReadSoAStalePlaceIsRefused() throws {
        let (service, book) = fixture()
        #expect(book.browseDate == nil)
        service.receivePosition(phone(book, reading: 1, at: 50, place: 6, placedAt: 90))
        #expect(service.currentBook?.browseWordIndex == 2)
        // The control: one second after the last read is newer and moves it.
        service.receivePosition(phone(book, reading: 1, at: 50, place: 6, placedAt: 101))
        #expect(service.currentBook?.browseWordIndex == 6)
    }

    @Test func anAdoptedPlaceIsClampedToTheBook() {
        let (service, book) = fixture()
        service.receivePosition(phone(book, reading: 1, at: 50, place: 500, placedAt: 300))
        #expect(service.currentBook?.browseWordIndex == 9)
    }

    // MARK: - The phone is reading

    @Test func phoneHeartbeatsRaiseTheCardAndPersistAtMostEveryFewSeconds() throws {
        let (service, book) = fixture()
        service.clock = { Date(timeIntervalSince1970: 200) }
        service.receivePosition(live(book, place: 3, sentAt: 200, startedAt: 195))
        #expect(service.remotePresence(for: book.id)?.wordIndex == 3)
        #expect(storage.store.load().currentBook?.browseWordIndex == 3)

        service.clock = { Date(timeIntervalSince1970: 201) }
        service.receivePosition(live(book, place: 4, sentAt: 201, startedAt: 195))
        #expect(service.currentBook?.browseWordIndex == 4)
        // The watch store holds every book's text: it is not rewritten per heartbeat.
        #expect(storage.store.load().currentBook?.browseWordIndex == 3)

        service.clock = { Date(timeIntervalSince1970: 202) }
        service.receivePosition(phone(book, reading: 5, at: 202))
        #expect(service.remotePresence == nil)
        #expect(storage.store.load().currentBook?.browseWordIndex == 5)
    }

    @Test func phoneScrubsPersistAtMostEveryFewSecondsAndTheLatestLands() async throws {
        // Mutation: persist every changed place at once. A scrub on the phone sends up to four
        // places a second, and each one rewrites the whole library, every book's text included.
        let (service, book) = fixture()
        service.livePersistInterval = 0.5
        service.clock = { Date(timeIntervalSince1970: 300) }
        service.receivePosition(phone(book, reading: 2, at: 100, place: 4, placedAt: 300))
        #expect(storage.store.load().currentBook?.browseWordIndex == 4)

        service.clock = { Date(timeIntervalSince1970: 300.1) }
        service.receivePosition(phone(book, reading: 2, at: 100, place: 5, placedAt: 300.1))
        service.clock = { Date(timeIntervalSince1970: 300.2) }
        service.receivePosition(phone(book, reading: 2, at: 100, place: 6, placedAt: 300.2))
        #expect(service.currentBook?.browseWordIndex == 6)
        #expect(storage.store.load().currentBook?.browseWordIndex == 4)

        for _ in 0..<40 where storage.store.load().currentBook?.browseWordIndex != 6 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(storage.store.load().currentBook?.browseWordIndex == 6, "The trailing write lands the latest place")
    }

    @Test func thePhoneTakingTheBookMakesTheWatchYield() {
        let (service, book) = fixture()
        service.clock = { Date(timeIntervalSince1970: 200) }
        var yielded: RemotePresence?
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { yielded = $0 })
        service.receivePosition(live(book, place: 8, sentAt: 201, startedAt: 201))
        #expect(yielded?.wordIndex == 8)
        #expect(service.localRunBookId == nil)
        #expect(service.currentBook?.browseWordIndex == 8)
    }

    @Test func aTieGoesToThePhone() {
        let (service, book) = fixture()
        service.clock = { Date(timeIntervalSince1970: 200) }
        var yielded = false
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { _ in yielded = true })
        service.receivePosition(live(book, place: 8, sentAt: 200, startedAt: 200))
        #expect(yielded)
    }

    @Test func anOlderPhoneRunCannotMoveTheWatchWhileItReads() {
        let (service, book) = fixture()
        service.clock = { Date(timeIntervalSince1970: 200) }
        var yielded = false
        service.beginLocalRun(bookId: book.id, snapshot: { nil }, onYield: { _ in yielded = true })
        service.receivePosition(live(book, place: 8, sentAt: 200, startedAt: 150))
        #expect(!yielded)
        #expect(service.localRunBookId == book.id)
        #expect(service.currentBook?.browseWordIndex == 2)
        service.endLocalRun(bookId: book.id)
    }

    // MARK: - The RSVP session follows and yields

    @Test func pausedWatchFollowsThePhonePlace() throws {
        let session = WatchRSVPSession()
        #expect(session.follow(placeAt: 5) == nil, "An unloaded engine has nothing to move")
        let (_, book) = fixture()
        _ = session.load(book: book, wpm: 300)
        #expect(session.engine.currentIndex == 2)
        #expect(session.follow(placeAt: 2) == nil, "Same word: no echo back to the crown")
        let crown = try #require(session.follow(placeAt: 6))
        #expect(session.engine.currentIndex == 6)
        #expect(crown == session.synchronizeCrownValue())
    }

    @Test func aPlayingWatchDoesNotFollowButYieldsToATakeover() {
        let session = WatchRSVPSession()
        let (_, book) = fixture()
        _ = session.load(book: book, wpm: 300)
        _ = session.togglePlayback(book: book)
        #expect(session.engine.state == .playing)
        #expect(session.follow(placeAt: 6) == nil)
        #expect(session.engine.currentIndex == 2)

        _ = session.yield(to: RemotePresence(bookId: book.id, wordIndex: 7,
                                             playStartedAt: .distantPast, sentAt: .distantPast))
        #expect(session.engine.state == .paused)
        #expect(session.engine.currentIndex == 7)
        // Mutation: drop the policy reset from the yield; leaving would then commit the
        // phone's word as the watch's newer reading and roll the still-playing phone back.
        #expect(session.close(book: book) == nil)
    }

    @Test func aWatchThatPlayedAndWasNotTakenOverCommitsOnLeaving() throws {
        // The control for the yield above: without a yield, leaving commits.
        let session = WatchRSVPSession()
        let (_, book) = fixture()
        _ = session.load(book: book, wpm: 300)
        _ = session.togglePlayback(book: book)
        #expect(try #require(session.close(book: book)).wordIndex == 2)
    }

    // MARK: - The card and the takeover

    @Test func theCardCoversTheWordOnlyWhileThePhoneReadsThisBook() throws {
        let (service, book) = fixture()
        let session = WatchRSVPSession()
        var crown = 0.0
        let content = WatchRSVPContent(syncService: service, session: session, showSettings: .constant(false),
            crownValue: Binding(get: { crown }, set: { crown = $0 }), wpm: 300)
        content.load()
        let quiet = try PresentationRaster(content, width: 198, height: 242)
        #expect(quiet == (try PresentationRaster(content, width: 198, height: 242)),
                "The quiet render is stable, so a difference is the card")

        service.clock = { Date() }
        service.receivePosition(live(book, place: 2, sentAt: Date().timeIntervalSince1970,
                                     startedAt: Date().timeIntervalSince1970))
        let covered = try PresentationRaster(content, width: 198, height: 242)
        #expect(covered != quiet)
        let card = WatchReadingElsewhereCard(presence: try #require(service.remotePresence), book: book, onReadHere: {})
        #expect(try PresentationRaster(card, width: 198, height: 242) != quiet)
    }

    @Test func readHereTakesTheBookOverFromThePhone() throws {
        let (service, book) = fixture()
        let session = WatchRSVPSession()
        var crown = 0.0
        let content = WatchRSVPContent(syncService: service, session: session, showSettings: .constant(false),
            crownValue: Binding(get: { crown }, set: { crown = $0 }), wpm: 300)
        content.load()
        let now = Date().timeIntervalSince1970
        service.clock = { Date() }
        service.receivePosition(live(book, place: 6, sentAt: now, startedAt: now))
        #expect(session.follow(placeAt: 6) != nil)

        // The crown is inert under the card.
        content.seek(crown + 3)
        #expect(session.engine.currentIndex == 6)

        // "Read here" is an ordinary play at the phone's word.
        content.togglePlayback()
        #expect(session.engine.state == .playing)
        #expect(session.engine.currentIndex == 6)
        #expect(service.localRunBookId == book.id)
        #expect(service.remotePresence(for: book.id) == nil)
        content.togglePlayback()
        #expect(service.localRunBookId == nil)
    }

    // MARK: - Fixtures

    private func fixture() -> (WatchSyncService, WatchBook) {
        let book = WatchBook(
            id: UUID(), title: "Handoff", author: "",
            text: (0..<10).map { "w\($0)" }.joined(separator: " "),
            lastReadIndex: 2, lastReadDate: Date(timeIntervalSince1970: 100),
            wordCount: 10, dateAdded: Date(timeIntervalSince1970: 1)
        )
        let service = WatchSyncService(session: HandoffWatchSession(), store: storage.store)
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        return (service, book)
    }

    private func phone(_ book: WatchBook, reading: Int, at time: Double,
                       place: Int? = nil, placedAt: Double? = nil) -> WatchSyncLogic.PositionPayload {
        .init(bookId: book.id, bookTitle: book.title, wordIndex: reading,
              timestamp: Date(timeIntervalSince1970: time), furthestReadWordIndex: reading,
              browseWordIndex: place, browseTimestamp: placedAt.map { Date(timeIntervalSince1970: $0) })
    }

    private func live(_ book: WatchBook, place: Int, sentAt: Double,
                      startedAt: Double) -> WatchSyncLogic.PositionPayload {
        .init(bookId: book.id, bookTitle: book.title, wordIndex: 0,
              timestamp: Date(timeIntervalSince1970: 1),
              browseWordIndex: place, browseTimestamp: Date(timeIntervalSince1970: sentAt),
              isPlaying: true, playStartedAt: Date(timeIntervalSince1970: startedAt),
              sentAt: Date(timeIntervalSince1970: sentAt))
    }
}

@MainActor
private final class HandoffWatchSession: WatchConnectivitySession {
    struct Transfer {}

    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .activated
    var isReachable = false

    func activate() {}

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {}

    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer { Transfer() }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {}
}
