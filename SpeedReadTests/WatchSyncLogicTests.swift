import Foundation
import Testing
@testable import SpeedRead

@Suite("Watch Sync Logic")
@MainActor
struct WatchSyncLogicTests {
    @Test func bookPayloadRoundTrip() throws {
        let original = WatchSyncLogic.BookPayload(
            id: UUID(),
            title: "A Book",
            author: "An Author",
            text: "one two three",
            wordCount: 3
        )

        let decoded = try #require(WatchSyncLogic.BookPayload.decode(from: original.dictionary))
        #expect(decoded == original)
    }

    @Test func fileMetadataAndInlineTextRoundTrip() throws {
        let original = WatchSyncLogic.BookPayload(
            id: UUID(), title: "Title", author: "Author", text: "file body", wordCount: 2
        )

        let decoded = try #require(
            WatchSyncLogic.BookPayload.decode(from: original.fileMetadata, inlineText: original.text)
        )
        #expect(decoded == original)
    }

    @Test func positionPayloadRoundTrip() throws {
        let original = WatchSyncLogic.PositionPayload(
            bookId: UUID(),
            bookTitle: "Title",
            wordIndex: 42,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            furthestReadWordIndex: 84
        )

        let decoded = try #require(WatchSyncLogic.PositionPayload.decode(from: original.dictionary))
        #expect(decoded == original)
        #expect(original.dictionary["browseWordIndex"] == nil)
    }

    @Test("Characterization: reading position is timestamp LWW, not max")
    func readingPositionUsesTimestampNotMagnitude() {
        let newerLower = WatchSyncLogic.PositionPayload(
            bookId: UUID(), bookTitle: "Book", wordIndex: 4,
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let olderHigher = WatchSyncLogic.PositionPayload(
            bookId: newerLower.bookId, bookTitle: "Book", wordIndex: 90,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        #expect(WatchSyncLogic.reconcile(
            incoming: newerLower,
            bookExists: true,
            lastReadDate: Date(timeIntervalSince1970: 200)
        ) == .apply)
        #expect(WatchSyncLogic.reconcile(
            incoming: olderHigher,
            bookExists: true,
            lastReadDate: Date(timeIntervalSince1970: 200)
        ) == .ignoreStale)
    }

    @Test func furthestReadMergesByMaxRegardlessOfArrivalOrder() {
        #expect(WatchSyncLogic.mergedFurthestRead(local: 80, incoming: 20) == 80)
        #expect(WatchSyncLogic.mergedFurthestRead(local: 20, incoming: 80) == 80)
        #expect(WatchSyncLogic.mergedFurthestRead(local: 80, incoming: 80) == 80)
    }

    @Test func watchOfferRequiresNewerMateriallyDifferentReadingPosition() {
        let localDate = Date(timeIntervalSince1970: 200)
        let material = WatchSyncLogic.PositionPayload(
            bookId: UUID(), bookTitle: "Book", wordIndex: 30,
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let trivial = WatchSyncLogic.PositionPayload(
            bookId: material.bookId, bookTitle: "Book", wordIndex: 12,
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let stale = WatchSyncLogic.PositionPayload(
            bookId: material.bookId, bookTitle: "Book", wordIndex: 90,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        #expect(WatchSyncLogic.shouldOfferWatchPosition(
            incoming: material, localIndex: 10, localDate: localDate, wordCount: 1_000
        ))
        #expect(!WatchSyncLogic.shouldOfferWatchPosition(
            incoming: trivial, localIndex: 10, localDate: localDate, wordCount: 1_000
        ))
        #expect(!WatchSyncLogic.shouldOfferWatchPosition(
            incoming: stale, localIndex: 10, localDate: localDate, wordCount: 1_000
        ))
    }

    @Test func newerPositionWins() {
        let incoming = position(at: 200)
        #expect(
            WatchSyncLogic.reconcile(
                incoming: incoming,
                bookExists: true,
                lastReadDate: Date(timeIntervalSince1970: 100)
            ) == .apply
        )
    }

    @Test func equalPositionTimestampIsIgnored() {
        let incoming = position(at: 200)
        #expect(
            WatchSyncLogic.reconcile(
                incoming: incoming,
                bookExists: true,
                lastReadDate: Date(timeIntervalSince1970: 200)
            ) == .ignoreStale
        )
    }

    @Test func olderPositionIsIgnored() {
        let incoming = position(at: 100)
        #expect(
            WatchSyncLogic.reconcile(
                incoming: incoming,
                bookExists: true,
                lastReadDate: Date(timeIntervalSince1970: 200)
            ) == .ignoreStale
        )
    }

    @Test func unknownBookIsIgnored() {
        #expect(
            WatchSyncLogic.reconcile(
                incoming: position(at: 200),
                bookExists: false,
                lastReadDate: nil
            ) == .ignoreUnknownBook
        )
    }

    @Test func deliverySelectsMessageThenFileFallback() {
        #expect(WatchSyncLogic.initialBookDeliveryRoute(isReachable: true) == .message)
        #expect(WatchSyncLogic.bookDeliveryRouteAfterMessageFailure() == .file)
    }

    @Test func unreachableCounterpartSelectsFileTransfer() {
        #expect(WatchSyncLogic.initialBookDeliveryRoute(isReachable: false) == .file)
    }

    @Test func malformedAndPartialBookPayloadsAreRejected() {
        let validId = UUID().uuidString
        #expect(WatchSyncLogic.BookPayload.decode(from: ["title": "Missing fields"]) == nil)
        #expect(WatchSyncLogic.BookPayload.decode(from: [
            "id": "not-a-uuid", "title": "T", "author": "A", "text": "body", "wordCount": 1
        ]) == nil)
        #expect(WatchSyncLogic.BookPayload.decode(from: [
            "id": validId, "title": "T", "author": "A", "text": "body", "wordCount": -1
        ]) == nil)
    }

    @Test func malformedAndPartialPositionPayloadsAreRejected() {
        let validId = UUID().uuidString
        #expect(WatchSyncLogic.PositionPayload.decode(from: ["bookId": validId]) == nil)
        #expect(WatchSyncLogic.PositionPayload.decode(from: [
            "bookId": validId, "bookTitle": "T", "wordIndex": -1, "timestamp": 100.0
        ]) == nil)
        #expect(WatchSyncLogic.PositionPayload.decode(from: [
            "bookId": "bad", "bookTitle": "T", "wordIndex": 1, "timestamp": 100.0
        ]) == nil)
    }

    private func position(at timestamp: TimeInterval) -> WatchSyncLogic.PositionPayload {
        WatchSyncLogic.PositionPayload(
            bookId: UUID(),
            bookTitle: "Title",
            wordIndex: 10,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
