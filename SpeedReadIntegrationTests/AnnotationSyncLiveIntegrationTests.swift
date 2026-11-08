import Foundation
import SwiftData
import Testing
@testable import SpeedRead

/// Highlights, notes and bookmarks through a live CWNG server, between two devices that each
/// downloaded the book themselves — the whole promise, with nothing scripted in between.
///
/// Enabled by the OPDS live variables plus the server's id for a copy of Kafka's *The
/// Metamorphosis* (the KOReader test plants a highlight by that EPUB's own XPointers):
///
///     SPEEDREAD_LIVE_OPDS=1 SPEEDREAD_TEST_OPDS_URL=http://127.0.0.1:18086/opds/ \
///     SPEEDREAD_TEST_OPDS_USER=... SPEEDREAD_TEST_OPDS_PASSWORD=... \
///     SPEEDREAD_TEST_ANNOTATION_BOOK_ID=221 \
///     xcodebuild test ... -testPlan Integration
///
/// The server never hard-deletes an annotation, so every run uses fresh ids and leaves tombstones.
@Suite("Annotation sync live", .serialized)
@MainActor
struct AnnotationSyncLiveIntegrationTests {
    nonisolated private static let env = ProcessInfo.processInfo.environment
    nonisolated private static let liveURL =
        URL(string: env["SPEEDREAD_TEST_OPDS_URL"] ?? "") ?? URL(string: "https://unconfigured.invalid/opds/")!
    nonisolated private static let username = env["SPEEDREAD_TEST_OPDS_USER"] ?? ""
    nonisolated private static let password = env["SPEEDREAD_TEST_OPDS_PASSWORD"] ?? ""
    nonisolated private static let bookID = env["SPEEDREAD_TEST_ANNOTATION_BOOK_ID"] ?? ""

    nonisolated private static let liveEnabled =
        env["SPEEDREAD_LIVE_OPDS"] == "1"
        && !(env["SPEEDREAD_TEST_OPDS_URL"] ?? "").isEmpty
        && !username.isEmpty && !password.isEmpty && !bookID.isEmpty

    @Test(.enabled(if: AnnotationSyncLiveIntegrationTests.liveEnabled))
    func highlightsNotesBookmarksAndDeletesTravelBetweenDevices() async throws {
        let epub = try await Self.downloadBook()
        let phone = try Device(name: "phone", epub: epub), tablet = try Device(name: "tablet", epub: epub)
        defer { phone.close(); tablet.close() }
        #expect(phone.book.words == tablet.book.words)

        let start = phone.book.words.count / 3 + Int.random(in: 0..<2_000), end = start + 4
        let note = "live note \(UUID().uuidString.prefix(8))"
        let highlight = phone.addHighlight(start, end, note: note)
        let bookmark = phone.addBookmark(start + 40)
        await phone.sync.sync(bookId: phone.book.id)
        #expect(!highlight.needsPush(by: phone.sync.deviceID))
        #expect(!bookmark.needsPush(by: phone.sync.deviceID))

        // The server placed both on its own copy, so KOReader and the web reader see them too.
        let stored = try await phone.rawRows()
        let storedHighlight = try #require(stored[highlight.annotationID.lowercased()])
        #expect(storedHighlight["source"] as? String == "textquote")
        #expect(storedHighlight["type"] as? String == "highlight")
        #expect(storedHighlight["note_text"] as? String == note)
        #expect(storedHighlight["start_xpointer"] is String, "the server could not place the quote")
        let storedBookmark = try #require(stored[bookmark.annotationID.lowercased()])
        #expect(storedBookmark["type"] as? String == "dogear")

        await tablet.sync.sync(bookId: tablet.book.id)
        let highlightCopy = try #require(tablet.highlight(highlight.annotationID))
        #expect(highlightCopy.startWordIndex == start)
        #expect(highlightCopy.endWordIndex == end)
        #expect(highlightCopy.note == note)
        #expect(tablet.bookmark(bookmark.annotationID)?.wordIndex == start + 40)

        // The server lets only the device that made a row change it (CWNG v4.1.48+). The tablet is
        // not offered the edit, and an attempt anyway is neither kept nor sent.
        #expect(!highlightCopy.isOwned(by: tablet.sync.deviceID))
        #expect(AnnotationListLogic.noteAccess(for: highlightCopy, deviceID: tablet.sync.deviceID)
            == .readOnly("Added on another device. Change its note there."))
        let before = try #require(try await phone.rawRows()[highlight.annotationID.lowercased()])
        tablet.sync.setNote("edited on the tablet", on: highlightCopy, in: tablet.context)
        #expect(highlightCopy.note == note)
        await tablet.sync.sync(bookId: tablet.book.id)
        let untouched = try #require(try await phone.rawRows()[highlight.annotationID.lowercased()])
        #expect(untouched["note_text"] as? String == note)
        #expect(untouched["content_revision"] as? Int == before["content_revision"] as? Int)
        #expect(untouched["server_modified_at"] as? String == before["server_modified_at"] as? String)

        // The owner's edit travels.
        phone.sync.setNote("edited on the phone", on: highlight, in: phone.context)
        await phone.sync.sync(bookId: phone.book.id)
        await tablet.sync.sync(bookId: tablet.book.id)
        #expect(highlightCopy.note == "edited on the phone")
        let edited = try await phone.rawRows()[highlight.annotationID.lowercased()]
        #expect(edited?["note_text"] as? String == "edited on the phone")
        #expect(edited?["device_origin_id"] as? String == phone.sync.deviceID, "an edit re-credited the highlight")

        phone.sync.delete(highlight, in: phone.context)
        phone.sync.delete(bookmark, in: phone.context)
        await phone.sync.sync(bookId: phone.book.id)
        let tombstones = try await phone.rawRows()
        #expect(tombstones[highlightCopy.annotationID.lowercased()]?["hidden"] as? Bool == true)
        #expect(tombstones[bookmark.annotationID.lowercased()]?["hidden"] as? Bool == true)

        await tablet.sync.sync(bookId: tablet.book.id)
        #expect(tablet.highlight(highlightCopy.annotationID) == nil)
        #expect(tablet.bookmark(bookmark.annotationID) == nil)
    }

    /// KOReader's own request shape: XPointers and the passage's text, no quote. The server derives
    /// the quote, and the app places it on the same words.
    @Test(.enabled(if: AnnotationSyncLiveIntegrationTests.liveEnabled))
    func aKOReaderHighlightArrivesOnItsWordsAndLeavesWhenKOReaderDeletesIt() async throws {
        let epub = try await Self.downloadBook()
        let phone = try Device(name: "phone", epub: epub)
        defer { phone.close() }
        let id = "live-ko-\(UUID().uuidString)"

        let planted = try await phone.putAsKOReader(#"""
        {"document":"\#(Self.bookID)","device":"KOReader","device_id":"live-ko","annotations":[{"annotation_id":"\#(id)","source":"koreader","type":"highlight","position_type":"koreader_xpointer","start_xpointer":"/body/DocFragment[5]/body/div[1]/p[2]/text().144","end_xpointer":"/body/DocFragment[5]/body/div[1]/p[2]/text().194","highlighted_text":"and it\ntook him long, long minutes to crawl across","color":"yellow","device_origin_id":"live-ko"}]}
        """#)
        #expect(planted["matched"] as? Bool == true)

        await phone.sync.sync(bookId: phone.book.id)
        let copy = try #require(phone.highlight(id), "the KOReader highlight was not adopted")
        #expect(copy.highlightedText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            == "and it took him long, long minutes to crawl across")
        #expect(copy.syncSource == "koreader")
        #expect(!copy.isOwned(by: phone.sync.deviceID))
        #expect(phone.book.words[copy.startWordIndex...copy.endWordIndex].joined(separator: " ")
            == copy.highlightedText.split(whereSeparator: \.isWhitespace).joined(separator: " "))

        _ = try await phone.putAsKOReader(#"""
        {"document":"\#(Self.bookID)","device":"KOReader","device_id":"live-ko","annotations":[],"deleted":["\#(id)"]}
        """#)
        await phone.sync.sync(bookId: phone.book.id)
        #expect(phone.highlight(id) == nil)
    }

    // MARK: Harness

    private static func configuration(for server: OPDSServer) -> OPDSRequestConfiguration {
        OPDSRequestConfiguration(server)
    }

    private static func downloadBook() async throws -> Data {
        let server = OPDSServer(name: "live-download", baseURL: liveURL, username: username,
                                allowInsecureHTTP: liveURL.scheme == "http")
        try KeychainStore.setPassword(password, for: server.keychainTag)
        defer { try? KeychainStore.deletePassword(for: server.keychainTag) }
        let download = try await OPDSClient().download(from: liveURL.appending(path: "download/\(bookID)/epub/"),
                                                       on: configuration(for: server))
        return download.data
    }

    /// One device: its own store, its own copy of the book, its own device id.
    @MainActor
    private final class Device {
        let container: ModelContainer
        let context: ModelContext
        let server: OPDSServer
        let book: Book
        let sync: ServerAnnotationSync
        private let suite: String

        init(name: String, epub: Data) throws {
            container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = container.mainContext
            server = OPDSServer(name: "live-\(name)", baseURL: AnnotationSyncLiveIntegrationTests.liveURL,
                                username: AnnotationSyncLiveIntegrationTests.username,
                                allowInsecureHTTP: AnnotationSyncLiveIntegrationTests.liveURL.scheme == "http")
            try KeychainStore.setPassword(AnnotationSyncLiveIntegrationTests.password, for: server.keychainTag)
            context.insert(server)
            book = try DocumentImporter(modelContext: context).importData(
                epub, filename: "\(AnnotationSyncLiveIntegrationTests.bookID).epub",
                origin: BookOrigin(serverID: server.id, entryID: "urn:live", serverBookID: AnnotationSyncLiveIntegrationTests.bookID)
            )
            try context.save()
            suite = "live-annotation-sync-\(name)-\(UUID().uuidString)"
            sync = ServerAnnotationSync(defaults: UserDefaults(suiteName: suite)!,
                                        deviceName: "SpeedRead (live \(name))", pushDelay: .seconds(600))
            sync.configure(modelContainer: container)
        }

        func close() {
            try? KeychainStore.deletePassword(for: server.keychainTag)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }

        func addHighlight(_ start: Int, _ end: Int, note: String) -> Highlight {
            let highlight = Highlight(startWordIndex: start, endWordIndex: end,
                                      highlightedText: Highlight.captureText(from: book.words, start: start, end: end))
            highlight.note = note
            highlight.book = book
            context.insert(highlight)
            try? context.save()
            return highlight
        }

        func addBookmark(_ index: Int) -> Bookmark {
            let bookmark = Bookmark(wordIndex: index, previewText: Bookmark.previewText(from: book.words, at: index))
            bookmark.book = book
            context.insert(bookmark)
            try? context.save()
            return bookmark
        }

        func highlight(_ annotationID: String) -> Highlight? {
            book.highlights.first { $0.annotationID.caseInsensitiveCompare(annotationID) == .orderedSame }
        }

        func bookmark(_ annotationID: String) -> Bookmark? {
            book.bookmarks.first { $0.annotationID.caseInsensitiveCompare(annotationID) == .orderedSame }
        }

        /// Every row the server holds for the book, keyed by lowercased id, with the fields this
        /// app does not decode (the server's own anchors) still present.
        func rawRows() async throws -> [String: [String: Any]] {
            let base = try #require(KOSyncWire.kosyncBase(fromOPDS: server.baseURL))
            let (data, status) = try await KOSyncClient().send(
                KOSyncWire.annotationsFetchURL(base: base, document: AnnotationSyncLiveIntegrationTests.bookID),
                method: "GET", server: OPDSRequestConfiguration(server))
            #expect(status == 200)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rows = try #require(body["annotations"] as? [[String: Any]])
            return Dictionary(rows.compactMap { row in (row["annotation_id"] as? String).map { ($0.lowercased(), row) } },
                              uniquingKeysWith: { first, _ in first })
        }

        func putAsKOReader(_ body: String) async throws -> [String: Any] {
            let base = try #require(KOSyncWire.kosyncBase(fromOPDS: server.baseURL))
            let (data, status) = try await KOSyncClient().send(KOSyncWire.annotationsPushURL(base: base), method: "PUT",
                                                               server: OPDSRequestConfiguration(server), body: Data(body.utf8))
            #expect(status == 200)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }
}
