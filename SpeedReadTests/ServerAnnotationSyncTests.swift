import Foundation
import SwiftData
import Testing
@testable import SpeedRead

/// The service end to end against a scripted server: what is sent for a book's highlights,
/// notes and bookmarks, and what another reader's annotations become on this device.
@Suite("Server annotation sync", .serialized)
@MainActor
struct ServerAnnotationSyncTests {
    @Test func aNewHighlightIsSentAsItsWords() async throws {
        let f = try Fixture()
        defer { f.close() }
        let highlight = f.addHighlight(10, 12, note: "why")
        f.supportsAnnotations()
        f.serve(rows: [])
        f.pushAccepted()

        f.sync.noteChanged(bookId: f.book.id)
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL, f.pushURL])
        let body = try f.pushedBody(at: 2)
        #expect(body["document"] as? String == "42")
        #expect(body["device_id"] as? String == f.sync.deviceID)
        #expect(body["deleted"] as? [String] == [])
        let row = try #require((body["annotations"] as? [[String: Any]])?.first)
        #expect(row["annotation_id"] as? String == highlight.id.uuidString)
        #expect(row["type"] as? String == "highlight")
        #expect(row["note_text"] as? String == "why")
        #expect(row["percentage"] as? Double == 10.0 / 300)
        #expect(row["text_quote"] as? [String: String] == [
            "exact": "w10 w11 w12", "prefix": "w2 w3 w4 w5 w6 w7 w8 w9", "suffix": "w13 w14 w15 w16 w17 w18 w19 w20",
        ])
        #expect(!highlight.needsPush)
    }

    @Test func aBookmarkIsSentAsADogearOnItsWord() async throws {
        let f = try Fixture()
        defer { f.close() }
        let bookmark = f.addBookmark(0)
        f.supportsAnnotations()
        f.serve(rows: [])
        f.pushAccepted()

        await f.sync.sync(bookId: f.book.id)

        let row = try #require((try f.pushedBody(at: 2)["annotations"] as? [[String: Any]])?.first)
        #expect(row["type"] as? String == "dogear")
        #expect(row["text_quote"] as? [String: String] == ["exact": "w0", "prefix": "", "suffix": "w1 w2 w3 w4 w5 w6 w7 w8"])
        #expect(bookmark.syncedAt != nil)
    }

    @Test func nothingIsSentAgainWhenNothingChanged() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.addHighlight(10, 12)
        f.supportsAnnotations()
        f.serve(rows: [])
        f.pushAccepted()
        await f.sync.sync(bookId: f.book.id)
        f.serve(rows: [])

        await f.sync.sync(bookId: f.book.id)

        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL, f.pushURL, f.fetchURL])
    }

    @Test func anotherReadersHighlightArrivesOnTheSameWordsWithItsNote() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(rows: [f.row("kr-7", from: 50, to: 52, note: "from the kobo")])

        await f.sync.sync(bookId: f.book.id)

        let highlight = try #require(f.book.highlights.first)
        #expect(highlight.startWordIndex == 50)
        #expect(highlight.endWordIndex == 52)
        #expect(highlight.highlightedText == "w50 w51 w52")
        #expect(highlight.note == "from the kobo")
        #expect(highlight.syncID == "kr-7")
        #expect(highlight.syncSource == "koreader")
        #expect(!highlight.isEditableOnServer)
        // Nothing to send: the row came from the server.
        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL])
    }

    @Test func anotherReadersBookmarkArrivesAsABookmark() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(rows: [f.row("kr-8", from: 77, to: 77, type: "dogear")])

        await f.sync.sync(bookId: f.book.id)

        #expect(f.book.highlights.isEmpty)
        #expect(f.book.bookmarks.map(\.wordIndex) == [77])
    }

    @Test func aQuoteThisCopyDoesNotContainIsLeftOnTheServer() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(body: #"{"annotations":[{"annotation_id":"kr-9","source":"koreader","type":"highlight","hidden":false,"text_quote":{"exact":"not in this book","prefix":null,"suffix":null}}]}"#)

        await f.sync.sync(bookId: f.book.id)

        #expect(f.book.highlights.isEmpty)
    }

    @Test func aDeletionInAnotherReaderRemovesItHere() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(rows: [f.row("kr-7", from: 50, to: 52)])
        await f.sync.sync(bookId: f.book.id)
        #expect(f.book.highlights.count == 1)
        f.serve(rows: [f.row("kr-7", from: 50, to: 52, hidden: true)])

        await f.sync.sync(bookId: f.book.id)

        #expect(f.book.highlights.isEmpty)
    }

    @Test func anotherReadersHighlightDeletedHereStaysGone() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(rows: [f.row("kr-7", from: 50, to: 52)])
        await f.sync.sync(bookId: f.book.id)
        f.sync.delete(try #require(f.book.highlights.first), in: f.context)
        f.serve(rows: [f.row("kr-7", from: 50, to: 52)])

        await f.sync.flush()

        #expect(f.book.highlights.isEmpty)
        // Only KOReader may delete its own row, so nothing is sent.
        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL, f.fetchURL])
    }

    @Test func deletingThisAppsHighlightSendsANamedDelete() async throws {
        let f = try Fixture()
        defer { f.close() }
        let highlight = f.addHighlight(10, 12)
        let id = highlight.id.uuidString
        f.supportsAnnotations()
        f.serve(rows: [])
        f.pushAccepted()
        await f.sync.sync(bookId: f.book.id)

        f.sync.delete(highlight, in: f.context)
        // The server still has it until the delete lands; it must not come back meanwhile.
        f.serve(rows: [f.row(id, from: 10, to: 12, source: "textquote")])
        f.pushAccepted()
        await f.sync.flush()

        #expect(f.book.highlights.isEmpty)
        let body = try f.pushedBody(at: 4)
        #expect(body["deleted"] as? [String] == [id])
        #expect((body["annotations"] as? [Any])?.isEmpty == true)
        #expect(f.defaults.defaults.dictionary(forKey: ServerAnnotationSync.pendingDeletesKey)?[f.book.id.uuidString] == nil)
    }

    @Test func aNoteChangedHereIsSentAndOneChangedElsewhereIsTaken() async throws {
        let f = try Fixture()
        defer { f.close() }
        let highlight = f.addHighlight(10, 12)
        f.supportsAnnotations()
        f.serve(rows: [])
        f.pushAccepted()
        await f.sync.sync(bookId: f.book.id)

        f.sync.setNote("  a thought  ", on: highlight, in: f.context)
        f.serve(rows: [f.row(highlight.id.uuidString, from: 10, to: 12, source: "textquote", note: nil)])
        f.pushAccepted()
        await f.sync.flush()
        let sent = try #require((try f.pushedBody(at: 4)["annotations"] as? [[String: Any]])?.first)
        #expect(sent["note_text"] as? String == "a thought")
        #expect(highlight.note == "a thought")

        // Edited in the web reader since.
        f.serve(rows: [f.row(highlight.id.uuidString, from: 10, to: 12, source: "textquote", note: "edited there")])
        await f.sync.sync(bookId: f.book.id)
        #expect(highlight.note == "edited there")
        #expect(!highlight.needsPush)
    }

    @Test func aNoteAddedHereToAnotherDevicesHighlightKeepsItCreditedToThatDevice() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.supportsAnnotations()
        f.serve(rows: [f.row("phone-1", from: 30, to: 31, source: "textquote")])
        await f.sync.sync(bookId: f.book.id)
        let highlight = try #require(f.book.highlights.first)
        #expect(highlight.isEditableOnServer)

        f.sync.setNote("from the tablet", on: highlight, in: f.context)
        f.serve(rows: [f.row("phone-1", from: 30, to: 31, source: "textquote")])
        f.pushAccepted()
        await f.sync.sync(bookId: f.book.id)

        let row = try #require((try f.pushedBody(at: 3)["annotations"] as? [[String: Any]])?.first)
        #expect(row["annotation_id"] as? String == "phone-1")
        #expect(row["note_text"] as? String == "from the tablet")
        #expect(row["device_origin_id"] as? String == "OTHER")
    }

    @Test func anEditMadeWhileAPushIsOnTheWireIsStillSent() async throws {
        let f = try Fixture()
        defer { f.close() }
        let highlight = f.addHighlight(10, 12)
        f.supportsAnnotations()
        f.serve(rows: [])
        f.script.enqueue(f.pushURL, data: Data(#"{"created":1}"#.utf8), held: true)

        let running = Task { await f.sync.sync(bookId: f.book.id) }
        try await f.waitForRequests(3)
        highlight.setNote("typed during the push")
        f.script.release()
        await running.value

        #expect(highlight.needsPush)
    }

    @Test func aFailedPushIsSentAgainAtTheNextFlush() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.addHighlight(10, 12)
        f.supportsAnnotations()
        f.serve(rows: [])
        f.script.enqueue(f.pushURL, status: 503)
        f.serve(rows: [])
        f.pushAccepted()

        f.sync.noteChanged(bookId: f.book.id)
        await f.sync.flush()
        await f.sync.flush()

        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL, f.pushURL, f.fetchURL, f.pushURL])
        #expect(f.script.remaining == 0)
    }

    @Test func aServerWithoutTheCapabilityIsAskedOnceAndNeverWrittenTo() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.addHighlight(10, 12)
        f.script.enqueue(f.authURL, data: Data(#"{"authorized":"OK","capabilities":["anchor"]}"#.utf8))

        await f.sync.sync(bookId: f.book.id)
        await f.sync.sync(bookId: f.book.id)

        #expect(f.script.observed.map(\.url) == [f.authURL])
    }

    @Test func aBookTheServerDoesNotHaveIsLeftAlone() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.addHighlight(10, 12)
        f.supportsAnnotations()
        f.serve(body: #"{"document":"42","annotations":[],"annotation_count":0,"book_known":false}"#)

        await f.sync.sync(bookId: f.book.id)

        #expect(f.script.observed.map(\.url) == [f.authURL, f.fetchURL])
    }

    @Test func nothingIsSentWhenTheServersSyncIsOffOrTheBookIsFromElsewhere() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.addHighlight(10, 12)
        f.server.syncsReadingPosition = false
        await f.sync.sync(bookId: f.book.id)
        f.server.syncsReadingPosition = true
        f.book.origin = nil
        await f.sync.sync(bookId: f.book.id)

        #expect(f.script.observed.isEmpty)
    }

    @Test func creatingAnnotationsInRSVPSchedulesASync() throws {
        let f = try Fixture()
        defer { f.close() }
        let recorder = RecordingAnnotationSync()
        let presentation = RSVPPresentationSession()
        presentation.load(book: f.book, engine: RSVPEngine(), wpm: 300)

        presentation.addBookmark(at: 5, book: f.book, modelContext: f.context, annotationSync: recorder)
        _ = presentation.toggleHighlight(at: 7, book: f.book, modelContext: f.context, annotationSync: recorder)
        _ = presentation.toggleHighlight(at: 9, book: f.book, modelContext: f.context, annotationSync: recorder)

        #expect(recorder.changed == [f.book.id, f.book.id])
    }

    // MARK: Fixture

    @MainActor
    private final class RecordingAnnotationSync: AnnotationChangeNoting {
        var changed: [UUID] = []
        func noteChanged(bookId: UUID) { changed.append(bookId) }
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let script = MockRequestScript()
        let defaults = IsolatedDefaults()
        let sync: ServerAnnotationSync
        let server: OPDSServer
        let book: Book
        let authURL = URL(string: "https://books.example.com/kosync/users/auth")!
        let fetchURL = URL(string: "https://books.example.com/kosync/syncs/annotations/42?text_quote=1")!
        let pushURL = URL(string: "https://books.example.com/kosync/syncs/annotations")!

        init() throws {
            container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = container.mainContext
            server = OPDSServer(name: "Library", baseURL: URL(string: "https://books.example.com/opds")!, username: "reader")
            try KeychainStore.setPassword("hunter2", for: server.keychainTag)
            book = Book(title: "Words", author: "A",
                        extractedText: (0..<300).map { "w\($0)" }.joined(separator: " "), sourceFileName: "words.epub")
            book.sourceDigest = "d1g35t"
            book.origin = BookOrigin(serverID: server.id, entryID: "urn:uuid:1", serverBookID: "42")
            context.insert(server)
            context.insert(book)
            try context.save()
            sync = ServerAnnotationSync(client: KOSyncClient(session: mockSession(script: script)),
                                        defaults: defaults.defaults, deviceName: "SpeedRead (Test)",
                                        pushDelay: .seconds(60))
            sync.configure(modelContainer: container)
        }

        func close() { script.close() }

        @discardableResult
        func addHighlight(_ start: Int, _ end: Int, note: String? = nil) -> Highlight {
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

        func supportsAnnotations() {
            script.enqueue(authURL, data: Data(#"{"authorized":"OK","capabilities":["anchor","annotations_text_quote"]}"#.utf8))
        }

        func serve(body: String) {
            script.enqueue(fetchURL, data: Data(body.utf8))
        }

        func serve(rows: [String]) {
            serve(body: #"{"annotations":[\#(rows.joined(separator: ","))],"annotation_count":\#(rows.count)}"#)
        }

        func pushAccepted() {
            script.enqueue(pushURL, data: Data(#"{"created":1,"updated":0,"deleted":0,"skipped":0}"#.utf8))
        }

        /// A row as the server returns it, quoting words `from...to` of this book.
        func row(_ id: String, from start: Int, to end: Int, source: String = "koreader", type: String = "highlight",
                 note: String? = nil, hidden: Bool = false) -> String {
            let quote = AnchoredText(book.extractedText).quote(fromToken: start, toToken: end)!
            let noteJSON = note.map { "\"\($0)\"" } ?? "null"
            return #"{"annotation_id":"\#(id)","source":"\#(source)","type":"\#(type)","hidden":\#(hidden),"note_text":\#(noteJSON),"device_origin_id":"OTHER","text_quote":{"exact":"\#(quote.exact)","prefix":"\#(quote.prefix)","suffix":"\#(quote.suffix)"}}"#
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
    }
}
