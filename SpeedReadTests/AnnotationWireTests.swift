import Foundation
import Testing
@testable import SpeedRead

/// Every byte of the annotation exchange, without a session.
@Suite("Annotation wire")
struct AnnotationWireTests {
    /// A pulled row in the shape the server's `to_portable` writes (field set read from the server
    /// source), with the `text_quote` the textquote contract adds. Replace with a captured
    /// response once the server half lands.
    static let pulledRow = #"""
    {"annotation_id":"kr-7","highlighted_text":"w10 w11","note_text":"remember this","color":"yellow",
     "content_id":null,"start_kobospan":null,"start_offset":null,"end_kobospan":null,"end_offset":null,
     "context_string":null,"chapter_progress":0.2,"position_type":"koreader_xpointer",
     "start_xpointer":"/body/DocFragment[2]/body/p[3]/text().0","end_xpointer":"/body/DocFragment[2]/body/p[3]/text().7",
     "type":"highlight","source":"koreader","hidden":false,"device_origin_id":"KOBO-1",
     "last_synced":"2026-10-03T22:13:05.123456",
     "text_quote":{"exact":"w10 w11","prefix":"w2 w3 w4 w5 w6 w7 w8 w9","suffix":null}}
    """#

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

    @Test func aPulledRowDecodesWithItsQuoteNoteAndOrigin() throws {
        let body = Data(#"{"annotations":[\#(Self.pulledRow)],"annotation_count":1}"#.utf8)
        let rows = try #require(try KOSyncWire.decodeAnnotations(body))
        let row = try #require(rows.first)
        #expect(row.annotationID == "kr-7")
        #expect(row.source == "koreader")
        #expect(row.type == .highlight)
        #expect(row.quote == TextQuote(exact: "w10 w11", prefix: "w2 w3 w4 w5 w6 w7 w8 w9", suffix: ""))
        #expect(row.note == "remember this")
        #expect(!row.hidden)
        #expect(row.deviceOriginID == "KOBO-1")
        #expect(!row.isTextQuoteSource)
        // A naive server time is UTC, microseconds and all.
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-03T22:13:05Z"))
        #expect(abs(try #require(row.updatedAt).timeIntervalSince(expected) - 0.123456) < 0.000_01)
    }

    @Test func aBookTheServerDoesNotHaveDecodesToNil() throws {
        let unknown = Data(#"{"document":"42","annotations":[],"annotation_count":0,"book_known":false}"#.utf8)
        #expect(try KOSyncWire.decodeAnnotations(unknown) == nil)
        #expect(try KOSyncWire.decodeAnnotations(Data(#"{"annotations":[]}"#.utf8)) == [])
    }

    @Test func oneUnreadableRowDoesNotLoseTheOthers() throws {
        let body = Data(#"{"annotations":[{"annotation_id":""},{"note_text":"no id"},\#(Self.pulledRow),{"annotation_id":17,"hidden":true}]}"#.utf8)
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

    @Test func pushResultsReportAnUnknownBook() {
        #expect(KOSyncWire.decodeAnnotationPushResult(Data(#"{"document":"42","matched":false,"created":0}"#.utf8)).matched == false)
        let result = KOSyncWire.decodeAnnotationPushResult(Data(#"{"created":2,"resolved":["A"],"unresolved":["B"]}"#.utf8))
        #expect(result == KOSyncAnnotationPushResult(matched: true, unresolved: ["B"]))
    }

    @Test func serverTimesInEveryShapeAPythonServerWrites() throws {
        let base = try #require(ISO8601DateFormatter().date(from: "2026-10-03T22:13:05Z"))
        #expect(KOSyncWire.serverDate("2026-10-03T22:13:05Z") == base)
        #expect(KOSyncWire.serverDate("2026-10-03T22:13:05+00:00") == base)
        #expect(KOSyncWire.serverDate("2026-10-03T18:13:05-04:00") == base)
        #expect(KOSyncWire.serverDate("2026-10-03T22:13:05") == base)
        #expect(KOSyncWire.serverDate("2026-10-03T22:13:05.5+00:00") == base.addingTimeInterval(0.5))
        #expect(KOSyncWire.serverDate("yesterday") == nil)
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
            == "https://books.example.com/kosync/syncs/annotations/42")
    }
}
