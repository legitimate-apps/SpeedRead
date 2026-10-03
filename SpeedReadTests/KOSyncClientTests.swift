import Foundation
import Testing
@testable import SpeedRead

/// Every byte the client puts on the wire, and how it reads every answer the server gives.
@Suite("KOSync client", .serialized)
struct KOSyncClientTests {
    // MARK: Wire

    @Test("the KOSync base sits beside the OPDS feed", arguments: [
        ("https://books.example.com/opds", "https://books.example.com/kosync"),
        ("https://books.example.com/opds/", "https://books.example.com/kosync"),
        ("https://books.example.com/calibre/OPDS", "https://books.example.com/calibre/kosync"),
        ("http://192.168.1.4:8083/opds?lang=en#top", "http://192.168.1.4:8083/kosync"),
    ])
    func kosyncBaseSitsBesideTheFeed(opds: String, expected: String) {
        #expect(KOSyncWire.kosyncBase(fromOPDS: URL(string: opds)) == URL(string: expected))
    }

    @Test func aFeedNotAtOPDSHasNoKnownSyncEndpoint() {
        #expect(KOSyncWire.kosyncBase(fromOPDS: URL(string: "https://books.example.com/feed")) == nil)
        #expect(KOSyncWire.kosyncBase(fromOPDS: URL(string: "https://books.example.com/")) == nil)
        #expect(KOSyncWire.kosyncBase(fromOPDS: nil) == nil)
    }

    @Test func fetchAsksForEveryPositionKind() {
        let url = KOSyncWire.fetchURL(base: URL(string: "https://h/kosync")!, document: "abc123")
        #expect(url?.absoluteString
            == "https://h/kosync/syncs/progress/abc123?position_kinds=locator,percentage,anchor")
    }

    @Test func onlyAnAnchorCapabilityMakesAServerPushable() {
        #expect(KOSyncWire.support(fromAuthBody: Data(#"{"authorized":"OK","capabilities":["position_kinds","percentage_push","anchor","book_id_document"]}"#.utf8)) == .anchorPositions)
        #expect(KOSyncWire.support(fromAuthBody: Data(#"{"authorized":"OK","capabilities":["position_kinds"]}"#.utf8)) == .unsupported)
        #expect(KOSyncWire.support(fromAuthBody: Data(#"{"authorized":"OK"}"#.utf8)) == .unsupported)
        #expect(KOSyncWire.support(fromAuthBody: Data("<html>".utf8)) == .unsupported)
    }

    @Test func aPushIsAPercentageAndAnAnchorWithNoProgress() throws {
        let push = KOSyncPush(document: "abc", percentage: 0.5, device: "SpeedRead (iPhone)", deviceID: "D-1",
                              anchor: ReadingAnchor(text: "his", before: "shouted", after: "sister,"))
        #expect(String(decoding: try KOSyncWire.encode(push), as: UTF8.self) == #"""
            {"anchor":{"after":"sister,","before":"shouted","text":"his"},"device":"SpeedRead (iPhone)","device_id":"D-1","document":"abc","percentage":0.5,"position_kind":"percentage"}
            """#)
        let bare = KOSyncPush(document: "42", percentage: 1, device: "d", deviceID: "D-1", anchor: nil)
        let json = String(decoding: try KOSyncWire.encode(bare), as: UTF8.self)
        #expect(!json.contains("anchor"))
        #expect(!json.contains("progress"))
    }

    @Test func anEmptyObjectIsNoPosition() throws {
        #expect(try KOSyncWire.decodePosition(Data("{}".utf8)) == nil)
        #expect(try KOSyncWire.decodePosition(Data(#"{"percentage":null,"device":"Kobo"}"#.utf8)) == nil)
    }

    @Test func aPositionDecodesWithNullContextAndAServerTimestamp() throws {
        let body = #"""
        {"percentage":0.6021,"position_kind":"locator","progress":"/body/DocFragment[7]/body/p[3]/text().0",
         "device":"Kobo Libra 2","device_id":"KOBO-1","timestamp":1790000000,"calibre_book_id":42,
         "anchor":{"text":"Gregor","before":null,"after":"woke"}}
        """#
        let position = try #require(try KOSyncWire.decodePosition(Data(body.utf8)))
        #expect(position == KOSyncRemotePosition(
            percentage: 0.6021, anchor: ReadingAnchor(text: "Gregor", before: "", after: "woke"),
            device: "Kobo Libra 2", deviceID: "KOBO-1", timestamp: Date(timeIntervalSince1970: 1_790_000_000)
        ))
    }

    /// Real bodies, not authored ones (2026-10-03, CWNG c6234f66d). The first was fetched by this
    /// client's own e2e run, escapes as the server sent them; the other two were captured by the
    /// server's session from the same build.
    @Test func sampledServerBodiesDecode() throws {
        let located = #"{"anchor":{"after":"try and get rid of it\u201d, said Gregor\u2019s","before":"Gregor as he lay there immobile. \u201cWe have","text":"to"},"calibre_book_format":"EPUB","calibre_book_id":221,"calibre_book_title":"Metamorphosis","calibre_checksum_version":"koreader","device":"KOReader","device_id":"KOREADER-E2E","document":"d9e3a7d72c664be1a12c0635bdb39520","percentage":0.7,"position_kind":"locator","progress":"/body/DocFragment[5]/body/div[1]/p[20]/text().10","timestamp":1791058063}"#
        let position = try #require(try KOSyncWire.decodePosition(Data(located.utf8)))
        #expect(position.percentage == 0.7)
        #expect(position.anchor == ReadingAnchor(text: "to", before: "Gregor as he lay there immobile. \u{201C}We have",
                                                 after: "try and get rid of it\u{201D}, said Gregor\u{2019}s"))
        #expect(position.device == "KOReader")
        #expect(position.deviceID == "KOREADER-E2E")
        #expect(position.timestamp == Date(timeIntervalSince1970: 1_791_058_063))

        let unplaced = #"{"calibre_book_id":3,"calibre_book_title":"The Republic","device":"WordReader (Phone)","device_id":"e2e-phone","document":"3","percentage":0.25,"position_kind":"percentage","progress":null,"timestamp":1791057431}"#
        let percentageOnly = try #require(try KOSyncWire.decodePosition(Data(unplaced.utf8)))
        #expect(percentageOnly.percentage == 0.25)
        #expect(percentageOnly.anchor == nil)

        #expect(try KOSyncWire.decodePosition(Data("{}".utf8)) == nil)
    }

    @Test func aHundredScalePercentageIsReadAsAFraction() throws {
        #expect(try KOSyncWire.decodePosition(Data(#"{"percentage":51.43}"#.utf8))?.percentage == 0.5143)
        #expect(try KOSyncWire.decodePosition(Data(#"{"percentage":-1}"#.utf8)) == nil)
    }

    // MARK: Client

    @Test func theProbeSendsTheOPDSCredentials() async throws {
        let f = Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, data: Data(#"{"authorized":"OK","capabilities":["anchor"]}"#.utf8))

        #expect(try await f.client.support(of: f.configuration) == .anchorPositions)

        let request = try #require(f.script.observed.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization")
            == "Basic " + Data("reader:hunter2".utf8).base64EncodedString())
        #expect(request.value(forHTTPHeaderField: "Accept") == KOSyncWire.accept)
    }

    @Test("a server that refuses Basic or has no KOSync is not an error", arguments: [401, 403, 404, 405])
    func refusalsAreUnsupported(status: Int) async throws {
        let f = Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: status)
        #expect(try await f.client.support(of: f.configuration) == .unsupported)
    }

    @Test func aServerErrorDuringTheProbeIsThrownSoItIsNotRemembered() async {
        let f = Fixture()
        defer { f.close() }
        f.script.enqueue(f.authURL, status: 502)
        await #expect(throws: OPDSError.httpError(status: 502)) {
            try await f.client.support(of: f.configuration)
        }
    }

    @Test func plainHTTPIsRefusedBeforeAnyRequest() async {
        let f = Fixture(base: "http://books.example.com/opds")
        defer { f.close() }
        await #expect(throws: OPDSError.insecureSchemeBlocked) {
            try await f.client.support(of: f.configuration)
        }
        #expect(f.script.observed.isEmpty)
    }

    @Test func aPushIsAJSONPut() async throws {
        let f = Fixture()
        defer { f.close() }
        let url = URL(string: "https://books.example.com/kosync/syncs/progress")!
        f.script.enqueue(url, data: Data(#"{"document":"abc","timestamp":1790000000}"#.utf8))
        let push = KOSyncPush(document: "abc", percentage: 0.25, device: "d", deviceID: "D-1", anchor: nil)

        try await f.client.push(push, to: f.configuration)

        let request = try #require(f.script.observed.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody ?? request.bodyStreamData == (try KOSyncWire.encode(push)))
    }

    @Test func aRejectedPushThrows() async {
        let f = Fixture()
        defer { f.close() }
        f.script.enqueue(URL(string: "https://books.example.com/kosync/syncs/progress")!, status: 400)
        await #expect(throws: OPDSError.httpError(status: 400)) {
            try await f.client.push(KOSyncPush(document: "abc", percentage: 0.25, device: "d", deviceID: "D", anchor: nil),
                                    to: f.configuration)
        }
    }

    @Test func aFetchReadsThePositionOrNothing() async throws {
        let f = Fixture()
        defer { f.close() }
        let hit = KOSyncWire.fetchURL(base: URL(string: "https://books.example.com/kosync")!, document: "abc")!
        let miss = KOSyncWire.fetchURL(base: URL(string: "https://books.example.com/kosync")!, document: "42")!
        f.script.enqueue(hit, data: Data(#"{"percentage":0.3,"device_id":"K","timestamp":1790000000}"#.utf8))
        f.script.enqueue(miss, data: Data("{}".utf8))

        #expect(try await f.client.position(of: "abc", on: f.configuration)?.percentage == 0.3)
        #expect(try await f.client.position(of: "42", on: f.configuration) == nil)
    }

    @Test func anUnreadableFetchIsAParseError() async {
        let f = Fixture()
        defer { f.close() }
        let url = KOSyncWire.fetchURL(base: URL(string: "https://books.example.com/kosync")!, document: "abc")!
        f.script.enqueue(url, data: Data("<html>".utf8))
        await #expect(throws: OPDSError.parseError) {
            try await f.client.position(of: "abc", on: f.configuration)
        }
    }

    private struct Fixture {
        let script = MockRequestScript()
        let client: KOSyncClient
        let configuration: OPDSRequestConfiguration
        let authURL = URL(string: "https://books.example.com/kosync/users/auth")!
        private let tag: String

        init(base: String = "https://books.example.com/opds") {
            client = KOSyncClient(session: mockSession(script: script))
            let server = OPDSServer(name: "Library", baseURL: URL(string: base)!, username: "reader")
            tag = server.keychainTag
            try? KeychainStore.setPassword("hunter2", for: tag)
            configuration = OPDSRequestConfiguration(server)
        }

        func close() {
            script.close()
            try? KeychainStore.deletePassword(for: tag)
        }
    }
}

extension URLRequest {
    /// URLProtocol receives a body set with `httpBody` as a stream.
    var bodyStreamData: Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
