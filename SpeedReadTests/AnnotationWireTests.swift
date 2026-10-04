import Foundation
import Testing
@testable import SpeedRead

/// Every byte of the annotation exchange, without a session.
@Suite("Annotation wire")
struct AnnotationWireTests {
    /// Captured verbatim from the CWNG rig (PR #2466, Metamorphosis = book 221), 2026-10-04:
    /// `GET /kosync/syncs/annotations/221?text_quote=1` after an inline delete of 4444. The server
    /// session trimmed rows 2–4 to the keys shown; the full rows carry every key row 1 does. Its test
    /// quote was cut at character offsets, hence "e darkness".
    static let capturedPull = #"""
    {"annotations":[{"annotation_id":"e2e-ko-2","chapter_progress":null,"color":"yellow","content_id":null,"content_revision":1,"context_string":null,"device_origin_id":"ko-dev","end_kobospan":null,"end_offset":null,"end_xpointer":"/body/DocFragment[5]/body/div[1]/p[2]/text().194","hidden":false,"highlighted_text":"and it\ntook him long, long minutes to crawl across","last_synced":"2026-10-04T01:51:48.094723","note_text":null,"position_type":"koreader_xpointer","server_modified_at":"2026-10-04T01:51:48.094723+00:00","source":"koreader","start_kobospan":null,"start_offset":null,"start_xpointer":"/body/DocFragment[5]/body/div[1]/p[2]/text().144","text_quote":{"exact":"and it took him long, long minutes to crawl across","prefix":"reduced to the condition of an ancient invalid","suffix":"his room—crawling over the ceiling was out of"},"type":"highlight"},{"annotation_id":"33333333-3333-4333-8333-333333333333","color":"yellow","content_revision":1,"device_origin_id":"tq-phone","end_xpointer":"/body/DocFragment[4]/body/div/p[3]/text().660","hidden":false,"highlighted_text":"e darkness, felt\na great pride that he was able to provide a life like that","note_text":"e2e note","position_type":"koreader_xpointer","server_modified_at":"2026-10-04T01:51:48.350172+00:00","source":"textquote","start_xpointer":"/body/DocFragment[4]/body/div/p[3]/text().585","text_quote":{"exact":"e darkness, felt a great pride that he was able to provide a life like that","prefix":"said Gregor to himself, and, gazing into th","suffix":"in such a nice home for his sister"},"type":"highlight"},{"annotation_id":"55555555-5555-4555-8555-555555555555","content_revision":1,"end_xpointer":"/body/DocFragment[4]/body/div/p[3]/text().663","hidden":false,"highlighted_text":null,"position_type":"koreader_xpointer","source":"textquote","start_xpointer":"/body/DocFragment[4]/body/div/p[3]/text().661","text_quote":{"exact":"in","prefix":"e darkness, felt a great pride that he was able to provide a life like that","suffix":"such a nice home for his sister"},"type":"dogear"},{"annotation_id":"44444444-4444-4444-8444-444444444444","content_revision":3,"hidden":true,"highlighted_text":"these words are certainly not in this book anywhere","position_type":"text_quote","server_modified_at":"2026-10-04T01:51:49.097448+00:00","source":"textquote","text_quote":{"exact":"these words are certainly not in this book anywhere","prefix":"","suffix":""},"type":"highlight"}],"book_known":true,"calibre_book_id":221,"document":"221"}
    """#

    /// Captured with it: the PUT response for a highlight, a dogear and a quote not in the book.
    static let capturedPushResponse = #"""
    {"calibre_book_id":221,"created":3,"deleted":0,"document":"221","matched":true,"reconciled":false,"resolved":["33333333-3333-4333-8333-333333333333","55555555-5555-4555-8555-555555555555"],"skipped":0,"unchanged":0,"unresolved":["44444444-4444-4444-8444-444444444444"],"updated":0}
    """#

    /// Captured: an invisible or unknown book id, status 200.
    static let capturedUnknownBook = #"{"annotation_count":0,"annotations":[],"book_known":false}"#

    @Test func aPushCarriesEachAnnotationAsItsWordsUnderThisAppsSource() throws {
        let push = KOSyncAnnotationPush(
            document: "42", device: "SpeedRead (iPhone)", deviceID: "dev-1",
            annotations: [
                .init(annotationID: "A", type: .highlight, quote: TextQuote(exact: "w1 w2", prefix: "w0", suffix: "w3"),
                      percentage: 0.25, note: "n", deviceOriginID: "dev-1"),
                .init(annotationID: "B", type: .dogear, quote: TextQuote(exact: "w9", prefix: "w8", suffix: ""),
                      percentage: 0.5, note: nil, deviceOriginID: "dev-1"),
            ],
            deleted: ["C"]
        )
        let json = try #require(JSONSerialization.jsonObject(with: KOSyncWire.encode(push)) as? [String: Any])
        #expect(json["document"] as? String == "42")
        #expect(json["device_id"] as? String == "dev-1")
        #expect(json["deleted"] as? [String] == ["C"])
        #expect(json["delete_source"] as? String == "textquote")
        let rows = try #require(json["annotations"] as? [[String: Any]])
        #expect(rows[0]["annotation_id"] as? String == "A")
        #expect(rows[0]["source"] as? String == "textquote")
        #expect(rows[0]["type"] as? String == "highlight")
        #expect(rows[0]["text_quote"] as? [String: String] == ["exact": "w1 w2", "prefix": "w0", "suffix": "w3"])
        #expect(rows[0]["note_text"] as? String == "n")
        #expect(rows[0]["percentage"] as? Double == 0.25)
        #expect(rows[0]["device_origin_id"] as? String == "dev-1")
        #expect(rows[0]["hidden"] as? Bool == false)
        #expect(rows[1]["type"] as? String == "dogear")
        // A removed note is sent as null, so it is removed on the server too.
        #expect(rows[1].keys.contains("note_text"))
        #expect(rows[1]["note_text"] is NSNull)
    }

    @Test func aCapturedPullDecodesEveryReadersRowsWithTheirQuotes() throws {
        let rows = try #require(try KOSyncWire.decodeAnnotations(Data(Self.capturedPull.utf8)))
        #expect(rows.map(\.annotationID) == ["e2e-ko-2", "33333333-3333-4333-8333-333333333333",
                                             "55555555-5555-4555-8555-555555555555", "44444444-4444-4444-8444-444444444444"])
        let koreader = rows[0]
        #expect(koreader.source == "koreader")
        #expect(!koreader.isTextQuoteSource)
        #expect(koreader.type == .highlight)
        #expect(koreader.quote == TextQuote(exact: "and it took him long, long minutes to crawl across",
                                            prefix: "reduced to the condition of an ancient invalid",
                                            suffix: "his room—crawling over the ceiling was out of"))
        #expect(koreader.note == nil)
        #expect(koreader.deviceOriginID == "ko-dev")
        #expect(rows[1].note == "e2e note")
        #expect(rows[1].isTextQuoteSource)
        #expect(rows[2].type == .dogear)
        #expect(rows[2].quote?.exact == "in")
        #expect(rows[3].hidden)
    }

    @Test func aCapturedUnknownBookDecodesToNil() throws {
        #expect(try KOSyncWire.decodeAnnotations(Data(Self.capturedUnknownBook.utf8)) == nil)
        #expect(try KOSyncWire.decodeAnnotations(Data(#"{"annotations":[]}"#.utf8)) == [])
    }

    @Test func oneUnreadableRowDoesNotLoseTheOthers() throws {
        let body = Data(#"{"annotations":[{"annotation_id":""},{"note_text":"no id"},{"annotation_id":"kr-7","source":"koreader"},{"annotation_id":17,"hidden":true}]}"#.utf8)
        let rows = try #require(try KOSyncWire.decodeAnnotations(body))
        #expect(rows.map(\.annotationID) == ["kr-7", "17"])
        #expect(rows[1].hidden)
        #expect(rows[1].quote == nil)
    }

    @Test func anEmptyNoteIsNoNoteAndAPercentageIsAFraction() throws {
        let body = Data(#"{"annotations":[{"annotation_id":"x","note_text":"","percentage":40}]}"#.utf8)
        let row = try #require(try KOSyncWire.decodeAnnotations(body)?.first)
        #expect(row.note == nil)
        #expect(row.percentage == 0.4)
    }

    @Test func aCapturedPushResultListsWhatTheServerCouldNotPlace() {
        let result = KOSyncWire.decodeAnnotationPushResult(Data(Self.capturedPushResponse.utf8))
        #expect(result == KOSyncAnnotationPushResult(matched: true, unresolved: ["44444444-4444-4444-8444-444444444444"]))
        #expect(KOSyncWire.decodeAnnotationPushResult(Data(#"{"document":"42","matched":false,"created":0}"#.utf8)).matched == false)
    }

    @Test func theCapabilityIsReadFromTheAuthAnswer() {
        let body = Data(#"{"authorized":"OK","capabilities":["anchor","annotations_text_quote"]}"#.utf8)
        #expect(KOSyncWire.capabilities(fromAuthBody: body).contains(KOSyncWire.textQuoteAnnotationsCapability))
        #expect(KOSyncWire.capabilities(fromAuthBody: Data(#"{"authorized":"OK"}"#.utf8)).isEmpty)
        #expect(KOSyncWire.capabilities(fromAuthBody: Data("<html>".utf8)).isEmpty)
    }

    @Test func annotationURLsSitBesideProgress() {
        let base = URL(string: "https://books.example.com/kosync")!
        #expect(KOSyncWire.annotationsPushURL(base: base).absoluteString == "https://books.example.com/kosync/syncs/annotations")
        #expect(KOSyncWire.annotationsFetchURL(base: base, document: "42").absoluteString
            == "https://books.example.com/kosync/syncs/annotations/42?text_quote=1")
    }
}
