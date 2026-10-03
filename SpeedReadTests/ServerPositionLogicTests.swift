import Foundation
import Testing
@testable import SpeedRead

@Suite("Server position logic")
struct ServerPositionLogicTests {
    private let server = UUID()

    // MARK: Keys

    @Test func aBookSyncsOnlyWithTheServerItCameFrom() {
        let origin = BookOrigin(serverID: server, entryID: "urn:uuid:1", serverBookID: "42")
        #expect(ServerPositionLogic.documentKeys(digest: "abc", origin: origin, serverID: server) == ["abc", "42"])
        #expect(ServerPositionLogic.documentKeys(digest: nil, origin: origin, serverID: server) == ["42"])
        #expect(ServerPositionLogic.documentKeys(digest: "abc", origin: origin, serverID: UUID()) == [])
        #expect(ServerPositionLogic.documentKeys(digest: "abc", origin: nil, serverID: server) == [])
        let noBookID = BookOrigin(serverID: server, entryID: "urn:uuid:1", serverBookID: nil)
        #expect(ServerPositionLogic.documentKeys(digest: nil, origin: noBookID, serverID: server) == [])
    }

    // MARK: Push

    @Test func anUnfinishedPositionNeverReachesTheServersFinishedMark() {
        #expect(ServerPositionLogic.pushPercentage(index: 500, wordCount: 1_000, finished: false) == 0.5)
        #expect(ServerPositionLogic.pushPercentage(index: 995, wordCount: 1_000, finished: false) == 0.989)
        #expect(ServerPositionLogic.pushPercentage(index: 999, wordCount: 1_000, finished: false)
            < ServerPositionLogic.finishedThreshold)
        #expect(ServerPositionLogic.pushPercentage(index: 999, wordCount: 1_000, finished: true) == 1)
        #expect(ServerPositionLogic.pushPercentage(index: 5, wordCount: 0, finished: false) == 0)
        #expect(ServerPositionLogic.pushPercentage(index: 5_000, wordCount: 1_000, finished: false) == 0.989)
    }

    // MARK: Placement

    private let text = AnchoredText((0..<200).map { "word\($0)" }.joined(separator: " "))

    @Test func anAnchorIsPreferredToThePercentage() {
        let remote = position(0.40, anchor: ReadingAnchor(text: "word90", before: "word88 word89", after: "word91 word92"))
        #expect(ServerPositionLogic.place(remote, in: text) == .init(index: 90, finished: false, anchored: true))
    }

    @Test func anAnchorThatCannotBePlacedFallsBackToThePercentage() {
        let remote = position(0.40, anchor: ReadingAnchor(text: "absent", before: "not in", after: "this book"))
        #expect(ServerPositionLogic.place(remote, in: text) == .init(index: 80, finished: false, anchored: false))
    }

    @Test func theServersFinishedMarkFinishesTheBookHere() {
        #expect(ServerPositionLogic.place(position(0.99), in: text) == .init(index: 199, finished: true, anchored: false))
        #expect(ServerPositionLogic.place(position(0.989), in: text)?.finished == false)
        #expect(ServerPositionLogic.place(position(0.5), in: AnchoredText("")) == nil)
    }

    // MARK: Offers

    private let me = "ME"
    private let read = Date(timeIntervalSince1970: 1_000)

    private func local(_ index: Int, finished: Bool = false, date: Date? = Date(timeIntervalSince1970: 1_000)) -> ServerPositionLogic.Local {
        .init(index: index, wordCount: 1_000, lastReadDate: date, finished: finished)
    }

    private func offer(_ remote: KOSyncRemotePosition, at index: Int, finished: Bool = false,
                       local: ServerPositionLogic.Local, declined: Date? = nil) -> Bool {
        ServerPositionLogic.shouldOffer(remote, placement: .init(index: index, finished: finished, anchored: true),
                                        local: local, deviceID: me, declinedTimestamp: declined)
    }

    @Test func aNewerPlaceFromAnotherReaderIsOffered() {
        #expect(offer(position(0.6, at: 2_000), at: 600, local: local(100)))
        #expect(offer(position(0.6, at: 2_000), at: 600, local: local(100, date: nil)))
    }

    @Test func ourOwnPushIsNeverOfferedBack() {
        #expect(!offer(position(0.6, at: 2_000, device: me), at: 600, local: local(100)))
    }

    @Test func aPlaceSetBeforeThisDeviceLastReadIsNotOffered() {
        // Furthest wins on the server, so after rereading an earlier chapter here the server
        // still holds the further place another reader set yesterday. It is not news.
        #expect(!offer(position(0.6, at: 1_000), at: 600, local: local(100)))
        #expect(!offer(position(0.6, at: 999), at: 600, local: local(100)))
    }

    @Test func aDeclinedOfferStaysDeclinedUntilTheServerMoves() {
        #expect(!offer(position(0.6, at: 2_000), at: 600, local: local(100), declined: Date(timeIntervalSince1970: 2_000)))
        #expect(offer(position(0.6, at: 2_001), at: 600, local: local(100), declined: Date(timeIntervalSince1970: 2_000)))
    }

    @Test func aPlaceWithinOnePercentIsWhereTheReaderAlreadyIs() {
        #expect(!offer(position(0.6, at: 2_000), at: 109, local: local(100)))
        #expect(offer(position(0.6, at: 2_000), at: 110, local: local(100)))
    }

    @Test func finishingElsewhereIsOfferedEvenAtTheSameWord() {
        #expect(offer(position(1, at: 2_000), at: 999, finished: true, local: local(999)))
        #expect(!offer(position(0.99, at: 2_000), at: 999, finished: true, local: local(999, finished: true)))
    }

    @Test func aPositionWithoutAReceiptTimeIsNotOffered() {
        let undated = KOSyncRemotePosition(percentage: 0.6, anchor: nil, device: nil, deviceID: "K", timestamp: nil)
        #expect(!offer(undated, at: 600, local: local(100)))
    }

    private func position(_ percentage: Double, anchor: ReadingAnchor? = nil, at seconds: Double = 2_000,
                          device: String = "KOBO") -> KOSyncRemotePosition {
        KOSyncRemotePosition(percentage: percentage, anchor: anchor, device: "Kobo", deviceID: device,
                             timestamp: Date(timeIntervalSince1970: seconds))
    }
}
