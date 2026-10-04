import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("Live phone↔watch handoff logic")
@MainActor
struct LiveHandoffLogicTests {
    private let bookId = UUID()

    private func payload(
        browse: Int = 40,
        browseAt: TimeInterval = 100,
        isPlaying: Bool = true,
        playStartedAt: TimeInterval? = 90,
        sentAt: TimeInterval = 100
    ) -> WatchSyncLogic.PositionPayload {
        WatchSyncLogic.PositionPayload(
            bookId: bookId,
            bookTitle: "Book",
            wordIndex: 10,
            timestamp: Date(timeIntervalSince1970: 50),
            furthestReadWordIndex: 10,
            browseWordIndex: browse,
            browseTimestamp: Date(timeIntervalSince1970: browseAt),
            isPlaying: isPlaying,
            playStartedAt: playStartedAt.map { Date(timeIntervalSince1970: $0) },
            sentAt: Date(timeIntervalSince1970: sentAt)
        )
    }

    // MARK: Place merge — last-write-wins on the move's time, never max

    @Test func newerMoveReplacesThePlaceEvenWhenItGoesBackward() {
        // A `max` rule would refuse a move to an earlier word; the place must follow it.
        #expect(LiveHandoffLogic.shouldApplyPlace(
            localDate: Date(timeIntervalSince1970: 99),
            incomingDate: Date(timeIntervalSince1970: 100)
        ))
    }

    @Test(arguments: [100.0, 101.0])
    func olderOrSimultaneousMoveKeepsThePlace(localTime: TimeInterval) {
        #expect(!LiveHandoffLogic.shouldApplyPlace(
            localDate: Date(timeIntervalSince1970: localTime),
            incomingDate: Date(timeIntervalSince1970: 100)
        ))
    }

    @Test func aPlaceThatWasNeverMovedTakesAnyIncomingMove() {
        #expect(LiveHandoffLogic.shouldApplyPlace(localDate: nil, incomingDate: .distantPast))
    }

    // MARK: Liveness reads the sender's clock, not the arrival time

    @Test(arguments: [
        (0.0, true), (5.9, true), (6.0, false), (60.0, false), (-1.0, true), (-6.0, false)
    ])
    func livenessWindow(age: TimeInterval, live: Bool) {
        let sent = Date(timeIntervalSince1970: 1_000)
        #expect(LiveHandoffLogic.isLive(sentAt: sent, now: sent.addingTimeInterval(age)) == live)
    }

    @Test func aFreshPlayingPayloadIsPresenceAtItsPlace() throws {
        let presence = try #require(LiveHandoffLogic.presence(
            from: payload(browse: 77), now: Date(timeIntervalSince1970: 101)
        ))
        #expect(presence == RemotePresence(
            bookId: bookId,
            wordIndex: 77,
            playStartedAt: Date(timeIntervalSince1970: 90),
            sentAt: Date(timeIntervalSince1970: 100)
        ))
    }

    @Test func aStaleContextDeliveredLateNeverRaisesPresence() {
        // An application context saying "playing" can arrive minutes after it was sent.
        #expect(LiveHandoffLogic.presence(
            from: payload(sentAt: 100), now: Date(timeIntervalSince1970: 400)
        ) == nil)
    }

    @Test func aPausedPayloadIsNotPresence() {
        #expect(LiveHandoffLogic.presence(
            from: payload(isPlaying: false), now: Date(timeIntervalSince1970: 100)
        ) == nil)
    }

    @Test func playingWithoutARunStartIsNotPresence() {
        #expect(LiveHandoffLogic.presence(
            from: payload(playStartedAt: nil), now: Date(timeIntervalSince1970: 100)
        ) == nil)
    }

    @Test func presenceExpiresOneWindowAfterItWasSent() throws {
        let presence = try #require(LiveHandoffLogic.presence(
            from: payload(sentAt: 100), now: Date(timeIntervalSince1970: 100)
        ))
        #expect(LiveHandoffLogic.expiry(of: presence) == Date(timeIntervalSince1970: 106))
    }

    // MARK: Yield — the later reading run owns the book

    @Test func aLaterRunOnTheOtherDeviceMakesThisOneYield() throws {
        let incoming = try #require(LiveHandoffLogic.presence(
            from: payload(playStartedAt: 95), now: Date(timeIntervalSince1970: 100)
        ))
        #expect(LiveHandoffLogic.shouldYield(
            localRunStartedAt: Date(timeIntervalSince1970: 94), incoming: incoming, localDevice: .phone
        ))
        #expect(LiveHandoffLogic.shouldYield(
            localRunStartedAt: Date(timeIntervalSince1970: 94), incoming: incoming, localDevice: .watch
        ))
    }

    @Test func anEarlierRunOnTheOtherDeviceIsIgnored() throws {
        let incoming = try #require(LiveHandoffLogic.presence(
            from: payload(playStartedAt: 95), now: Date(timeIntervalSince1970: 100)
        ))
        #expect(!LiveHandoffLogic.shouldYield(
            localRunStartedAt: Date(timeIntervalSince1970: 96), incoming: incoming, localDevice: .phone
        ))
        #expect(!LiveHandoffLogic.shouldYield(
            localRunStartedAt: Date(timeIntervalSince1970: 96), incoming: incoming, localDevice: .watch
        ))
    }

    @Test func aTieGoesToThePhone() throws {
        let incoming = try #require(LiveHandoffLogic.presence(
            from: payload(playStartedAt: 95), now: Date(timeIntervalSince1970: 100)
        ))
        let tie = Date(timeIntervalSince1970: 95)
        #expect(!LiveHandoffLogic.shouldYield(localRunStartedAt: tie, incoming: incoming, localDevice: .phone))
        #expect(LiveHandoffLogic.shouldYield(localRunStartedAt: tie, incoming: incoming, localDevice: .watch))
    }

    // MARK: Card text

    @Test func theCardNamesTheDeviceThatIsReading() {
        #expect(HandoffDevice.phone.counterpart == .watch)
        #expect(HandoffDevice.watch.counterpart == .phone)
        #expect(LiveHandoffLogic.cardTitle(readingOn: .watch) == "Reading on Apple Watch")
        #expect(LiveHandoffLogic.cardTitle(readingOn: .phone) == "Reading on iPhone")
    }

    @Test func theCardDetailGivesTheChapterAndPercentageAtTheLiveWord() {
        let presence = RemotePresence(bookId: bookId, wordIndex: 345, playStartedAt: .distantPast,
                                      sentAt: .distantPast)
        let chapters = [ChapterMark(title: "One", startWordIndex: 0),
                        ChapterMark(title: "Two", startWordIndex: 300),
                        ChapterMark(title: "Three", startWordIndex: 600)]
        #expect(LiveHandoffLogic.cardDetail(presence: presence, wordCount: 1_000, chapters: chapters)
                == "Two · 34%")
        #expect(LiveHandoffLogic.cardDetail(presence: presence, wordCount: 1_000, chapters: [])
                == "34%")
        #expect(LiveHandoffLogic.cardDetail(presence: presence, wordCount: 0, chapters: []) == "0%")
    }

    // MARK: Payload wire format

    @Test func livePayloadRoundTripsEveryField() throws {
        let original = payload(browse: 33, browseAt: 120, isPlaying: true, playStartedAt: 110, sentAt: 121)
        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: original.dictionary))
        #expect(decoded == original)
    }

    @Test func aPayloadFromBeforeLiveHandoffDecodesAsAPausedPlaceAtTheReadingPosition() throws {
        let legacy: [String: Any] = [
            "bookId": bookId.uuidString,
            "bookTitle": "Book",
            "wordIndex": 12,
            "timestamp": 500.0,
            "furthestReadWordIndex": 12,
            "didFinish": false
        ]
        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: legacy))
        #expect(decoded.browseWordIndex == 12)
        #expect(decoded.browseTimestamp == Date(timeIntervalSince1970: 500))
        #expect(decoded.isPlaying == false)
        #expect(decoded.playStartedAt == nil)
        #expect(decoded.sentAt == Date(timeIntervalSince1970: 500))
    }

    @Test func aNegativePlaceIsRejected() {
        var dictionary = payload().dictionary
        dictionary["browseWordIndex"] = -1
        #expect(WatchSyncLogic.PositionPayload.decode(from: dictionary) == nil)
    }
}
