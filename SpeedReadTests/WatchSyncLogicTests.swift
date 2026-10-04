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
            wordCount: 3,
            chapters: [
                ChapterMark(title: "Start", startWordIndex: 0),
                ChapterMark(title: "Later", startWordIndex: 2)
            ]
        )

        let decoded = try #require(WatchSyncLogic.BookPayload.decode(from: original.dictionary))
        #expect(decoded == original)
    }

    @Test func legacyBookPayloadWithoutChaptersDefaultsEmpty() throws {
        let dictionary: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Legacy",
            "author": "Author",
            "text": "one two",
            "wordCount": 2
        ]

        let decoded = try #require(WatchSyncLogic.BookPayload.decode(from: dictionary))

        #expect(decoded.chapters.isEmpty)
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
        // The place travels with every position now; it is the word both devices show.
        #expect(original.dictionary["browseWordIndex"] as? Int == 42)
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

    @Test(arguments: ["titleMissing", "titleEmpty", "titleType", "indexMissing", "indexNegative", "indexAtEnd", "indexType", "chaptersType"])
    func malformedChapterMetadataRejectsEntireBook(field: String) throws {
        let original = WatchSyncLogic.BookPayload(id: UUID(), title: "Book", author: "Author",
            text: "one two three", wordCount: 3,
            chapters: [ChapterMark(title: "Opening", startWordIndex: 0)])
        var dictionary = original.dictionary
        var chapters = try #require(dictionary["chapters"] as? [[String: Any]])
        switch field {
        case "titleMissing": chapters[0].removeValue(forKey: "title")
        case "titleEmpty": chapters[0]["title"] = ""
        case "titleType": chapters[0]["title"] = 123
        case "indexMissing": chapters[0].removeValue(forKey: "startWordIndex")
        case "indexNegative": chapters[0]["startWordIndex"] = -1
        case "indexAtEnd": chapters[0]["startWordIndex"] = 3
        case "indexType": chapters[0]["startWordIndex"] = "0"
        default: break
        }
        dictionary["chapters"] = field == "chaptersType" ? "corrupt" as Any : chapters as Any
        #expect(WatchSyncLogic.BookPayload.decode(from: dictionary) == nil)
        #expect(WatchSyncLogic.BookPayload.decode(from: dictionary, inlineText: original.text) == nil)
        // The control pins the legal last-word boundary, catching an overly strict repair.
        var valid = original.dictionary
        valid["chapters"] = [["title": "Last word", "startWordIndex": 2]]
        #expect(WatchSyncLogic.BookPayload.decode(from: valid)?.chapters == [ChapterMark(title: "Last word", startWordIndex: 2)])
    }

    @Test func legacyPayloadFallbacksDeriveCountAndHighWater() throws {
        // Mutation: replace missing wordCount with zero, tokenize without whitespace splitting,
        // or default missing furthestReadWordIndex to zero instead of the reading index.
        let id = UUID()
        let book = try #require(WatchSyncLogic.BookPayload.decode(from: [
            "id": id.uuidString, "title": "Legacy", "author": "", "text": "one  two\nthree"]))
        #expect(book.wordCount == 3)
        let position = try #require(WatchSyncLogic.PositionPayload.decode(from: [
            "bookId": id.uuidString, "bookTitle": "Legacy", "wordIndex": 7,
            "timestamp": 200.0]))
        #expect(position.furthestReadWordIndex == 7)
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
