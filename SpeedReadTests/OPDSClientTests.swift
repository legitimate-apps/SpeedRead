import Testing
import Foundation
import Synchronization
@testable import SpeedRead

private func makeServer(
    base: String = "https://books.example.com",
    user: String = "tester",
    allowInsecure: Bool = false
) -> OPDSServer {
    let server = OPDSServer(
        name: "Test",
        baseURL: URL(string: base)!,
        username: user,
        allowInsecureHTTP: allowInsecure
    )
    if !user.isEmpty {
        try? KeychainStore.setPassword("secret", for: server.keychainTag)
    }
    return server
}

private func tinyAtom(title: String = "Mock Feed") -> Data {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
        <title>\(title)</title>
        <id>urn:test:mock</id>
        <entry>
            <title>An Entry</title>
            <id>urn:entry:1</id>
            <link href="/sub" type="application/atom+xml;profile=opds-catalog"/>
        </entry>
    </feed>
    """
    return Data(xml.utf8)
}

@Suite("OPDS Client", .serialized)
struct OPDSClientTests {

    @Test func requestConfigurationDoesNotRetainMutableModelState() {
        let server = makeServer(user: "")
        let configuration = OPDSRequestConfiguration(server)
        let originalTag = server.keychainTag
        server.baseURLString = "http://changed.example.com"
        server.username = "changed"
        server.keychainTag = "changed"
        server.allowInsecureHTTP = true
        #expect(configuration.baseURL == URL(string: "https://books.example.com"))
        #expect(configuration.username.isEmpty)
        #expect(configuration.keychainTag == originalTag)
        #expect(!configuration.allowInsecureHTTP)
        #expect(!configuration.requiresAuth)
    }

    @Test func fetchFeedHappyPath() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://books.example.com/opds/")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/atom+xml"]
            )!
            return (resp, tinyAtom(title: "Live"))
        }
        let client = OPDSClient(session: mockSession())
        let feed = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        #expect(feed.title == "Live")
        #expect(feed.entries.count == 1)
    }

    @Test func fetchFeedSendsBasicAuthHeader() async throws {
        let server = makeServer(user: "alice")
        try KeychainStore.setPassword("rabbit", for: server.keychainTag)
        defer { try? KeychainStore.deletePassword(for: server.keychainTag) }

        let capturedAuth = Mutex<String?>(nil)
        MockURLProtocol.handler = { req in
            capturedAuth.withLock { $0 = req.value(forHTTPHeaderField: "Authorization") }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, tinyAtom())
        }
        let client = OPDSClient(session: mockSession())
        _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))

        let expectedCombo = "alice:rabbit".data(using: .utf8)!.base64EncodedString()
        #expect(capturedAuth.withLock { $0 } == "Basic \(expectedCombo)")
    }

    @Test func fetchFeedOmitsAuthHeaderWhenNoUsername() async throws {
        let server = makeServer(user: "")
        let capturedAuth = Mutex<String?>(nil)
        MockURLProtocol.handler = { req in
            capturedAuth.withLock { $0 = req.value(forHTTPHeaderField: "Authorization") }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, tinyAtom())
        }
        let client = OPDSClient(session: mockSession())
        _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        #expect(capturedAuth.withLock { $0 } == nil)
    }

    @Test func fetchFeedThrowsOn401() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = OPDSClient(session: mockSession())
        await #expect(throws: OPDSError.httpError(status: 401)) {
            _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        }
    }

    @Test func fetchFeedThrowsOn500() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = OPDSClient(session: mockSession())
        await #expect(throws: OPDSError.httpError(status: 503)) {
            _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        }
    }

    @Test func fetchFeedThrowsOnRedirectInsteadOfParsingItsBody() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/html",
                    "Location": "https://login.example.com/"
                ]
            )!
            return (resp, Data("<html>Sign in</html>".utf8))
        }
        let client = OPDSClient(session: mockSession())

        await #expect(throws: OPDSError.httpError(status: 302)) {
            _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        }
    }

    @Test func defaultInitializerUsesSharedSession() async {
        let client = OPDSClient()

        #expect(await client.session === URLSession.shared)
    }

    @Test func httpSchemeBlockedWhenInsecureDisabled() async throws {
        let server = makeServer(base: "http://insecure.example.com", allowInsecure: false)
        let client = OPDSClient(session: mockSession())
        await #expect(throws: OPDSError.insecureSchemeBlocked) {
            _ = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        }
    }

    @Test func httpSchemeAllowedWhenInsecureEnabled() async throws {
        let server = makeServer(base: "http://insecure.example.com", allowInsecure: true)
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, tinyAtom())
        }
        let client = OPDSClient(session: mockSession())
        let feed = try await client.fetchFeed(url: server.baseURL!, on: OPDSRequestConfiguration(server))
        #expect(feed.title == "Mock Feed")
    }

    @Test func downloadReturnsDataAndFilenameFromContentDisposition() async throws {
        let server = makeServer()
        let bookData = Data(repeating: 0x42, count: 256)
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/epub+zip",
                    "Content-Disposition": "attachment; filename=\"The Poppy War.epub\""
                ]
            )!
            return (resp, bookData)
        }
        let client = OPDSClient(session: mockSession())
        let url = URL(string: "https://books.example.com/opds/download/525/epub/")!
        let download = try await client.download(from: url, on: OPDSRequestConfiguration(server))
        #expect(download.data == bookData)
        #expect(download.filename == "The Poppy War.epub")
    }

    @Test func downloadFallsBackToURLLastComponentWhenNoDisposition() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("epub-bytes".utf8))
        }
        let client = OPDSClient(session: mockSession())
        let url = URL(string: "https://books.example.com/files/sample.epub")!
        let download = try await client.download(from: url, on: OPDSRequestConfiguration(server))
        #expect(download.filename == "sample.epub")
    }

    @Test func contentDispositionParsesFilenameStar() {
        let resp = HTTPURLResponse(
            url: URL(string: "https://x.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Disposition": "attachment; filename*=UTF-8''The%20Yellow%20Wallpaper.epub"]
        )!
        let name = OPDSClient.deriveFilename(response: resp, fallbackURL: URL(string: "https://x.test/")!)
        #expect(name == "The Yellow Wallpaper.epub")
    }

    /// CWNG's own header (helper.py): `filename=` and `filename*=` both percent-encoded, plain first.
    /// OBSERVED for an Arabic title. The decoded RFC 5987 value wins.
    @Test func contentDispositionPrefersTheExtendedFilenameOverAnEscapedPlainOne() {
        let escaped = "%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8"
        let resp = HTTPURLResponse(
            url: URL(string: "https://x.test")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Disposition": "attachment; filename=\(escaped).epub; filename*=UTF-8''\(escaped).epub"]
        )!
        #expect(OPDSClient.deriveFilename(response: resp, fallbackURL: URL(string: "https://x.test/")!)
            == "\u{627}\u{644}\u{643}\u{62A}\u{627}\u{628}.epub")
    }

    /// RFC 5987 names the charset; ISO-8859-1 is the other one it requires a reader to know.
    @Test func contentDispositionDecodesTheCharsetItNames() {
        let resp = HTTPURLResponse(
            url: URL(string: "https://x.test")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Disposition": "attachment; filename=\"rates.epub\"; filename*=iso-8859-1'en'%A3%20rates.epub"]
        )!
        #expect(OPDSClient.deriveFilename(response: resp, fallbackURL: URL(string: "https://x.test/")!) == "\u{A3} rates.epub")
    }

    /// A book is written to disk as it arrives rather than held in memory, and the caller owns
    /// the file it gets back.
    @Test func aBookDownloadsToAFileTheCallerOwns() async throws {
        let server = makeServer()
        let bookData = Data((0..<200_000).map { UInt8($0 % 251) })
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Disposition": "attachment; filename*=UTF-8''Big%20Book.pdf"])!
            return (resp, bookData)
        }
        let client = OPDSClient(session: mockSession())
        let file = try await client.downloadFile(from: URL(string: "https://books.example.com/opds/download/7/pdf/")!,
                                                 on: OPDSRequestConfiguration(server))
        defer { file.remove() }
        #expect(file.filename == "Big Book.pdf")
        #expect(try Data(contentsOf: file.location) == bookData)
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.location.path))
    }

    @Test func aRefusedBookDownloadLeavesNoFile() async throws {
        let server = makeServer()
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data("missing".utf8))
        }
        let client = OPDSClient(session: mockSession())
        let before = try OPDSDownloadedFile.directoryContents()
        await #expect(throws: OPDSError.httpError(status: 404)) {
            _ = try await client.downloadFile(from: URL(string: "https://books.example.com/opds/download/7/pdf/")!,
                                              on: OPDSRequestConfiguration(server))
        }
        #expect(try OPDSDownloadedFile.directoryContents() == before)
    }
}
