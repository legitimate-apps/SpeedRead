import Testing
import Foundation
import SwiftData
@testable import SpeedRead

/// End-to-end integration tests against a live Calibre-Web / CWNG instance.
///
/// The server address and credentials come from the environment and are
/// deliberately absent from this repository. Every test is
/// `.enabled(if: liveEnabled)`, so routine `xcodebuild test` runs skip them —
/// and they stay skipped unless *all* of the variables below are supplied:
///
///     xcodebuild test ... \
///       -only-testing:SpeedReadTests/OPDSLiveIntegrationTests \
///       SPEEDREAD_LIVE_OPDS=1 \
///       SPEEDREAD_TEST_OPDS_URL=https://example/opds/ \
///       SPEEDREAD_TEST_OPDS_USER=someuser \
///       SPEEDREAD_TEST_OPDS_PASSWORD=secret
///
/// Pre-condition: that server is reachable and the user exists in its `user`
/// table with read access to the catalog.
@Suite("OPDS Live Integration", .serialized)
struct OPDSLiveIntegrationTests {
    private static let env = ProcessInfo.processInfo.environment
    private static let liveURLString = env["SPEEDREAD_TEST_OPDS_URL"] ?? ""
    private static let username = env["SPEEDREAD_TEST_OPDS_USER"] ?? ""
    private static let password = env["SPEEDREAD_TEST_OPDS_PASSWORD"] ?? ""

    /// Falls back to an unroutable address so a misconfigured run fails fast
    /// and loudly rather than silently pointing somewhere real.
    private static let liveURL =
        URL(string: liveURLString) ?? URL(string: "https://unconfigured.invalid/opds/")!

    private static let liveEnabled =
        env["SPEEDREAD_LIVE_OPDS"] == "1"
        && !liveURLString.isEmpty
        && !username.isEmpty
        && !password.isEmpty

    private func makeServer() -> OPDSServer {
        let server = OPDSServer(
            name: "cwng-live",
            baseURL: Self.liveURL,
            username: Self.username,
            allowInsecureHTTP: false
        )
        try? KeychainStore.setPassword(Self.password, for: server.keychainTag)
        return server
    }

    private func teardown(_ server: OPDSServer) {
        try? KeychainStore.deletePassword(for: server.keychainTag)
    }

    @MainActor
    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test(.enabled(if: OPDSLiveIntegrationTests.liveEnabled))
    func fetchesRootCatalogFromLiveServer() async throws {
        let server = makeServer()
        defer { teardown(server) }
        let client = OPDSClient()
        let feed = try await client.fetchFeed(url: server.baseURL!, on: server)
        #expect(feed.title.contains("Calibre-Web"))
        #expect(!feed.entries.isEmpty)
        #expect(feed.searchTemplate != nil)
    }

    @Test(.enabled(if: OPDSLiveIntegrationTests.liveEnabled))
    func wrongPasswordSurfacesAs401() async throws {
        let server = OPDSServer(
            name: "wrong-creds",
            baseURL: Self.liveURL,
            username: Self.username,
            allowInsecureHTTP: false
        )
        try KeychainStore.setPassword("definitely-not-the-password", for: server.keychainTag)
        defer { try? KeychainStore.deletePassword(for: server.keychainTag) }
        let client = OPDSClient()
        await #expect(throws: OPDSError.httpError(status: 401)) {
            _ = try await client.fetchFeed(url: server.baseURL!, on: server)
        }
    }

    @Test(.enabled(if: OPDSLiveIntegrationTests.liveEnabled))
    func drillsIntoRecentlyAddedAndDownloadsAnEPUB() async throws {
        let server = makeServer()
        defer { teardown(server) }
        let client = OPDSClient()

        let root = try await client.fetchFeed(url: server.baseURL!, on: server)
        guard let recent = root.entries.first(where: { $0.title.localizedCaseInsensitiveContains("recently") || $0.title.localizedCaseInsensitiveContains("new") }),
              let recentURL = recent.navigationLink else {
            Issue.record("Live root feed did not expose a 'Recently added' navigation link")
            return
        }

        let recentFeed = try await client.fetchFeed(url: recentURL, on: server)
        let booksOnly = recentFeed.entries.filter { !$0.acquisitions.isEmpty }
        #expect(!booksOnly.isEmpty, "Recently-added feed had no acquisition entries")

        guard let firstBook = booksOnly.first,
              let epubAcquisition = firstBook.acquisitions.first(where: { $0.mimeType == "application/epub+zip" })
                ?? firstBook.acquisitions.first else {
            Issue.record("No acquisition link on the first recently-added book")
            return
        }

        let download = try await client.download(from: epubAcquisition.url, on: server)
        #expect(download.data.count > 0)
        #expect(!download.filename.isEmpty)

        let context = try await inMemoryContext()
        let filename = download.filename.hasSuffix(".epub") || download.filename.hasSuffix(".pdf")
            ? download.filename
            : (download.filename + ".epub")
        let book = try await MainActor.run {
            let importer = DocumentImporter(modelContext: context)
            return try importer.importData(download.data, filename: filename)
        }
        await MainActor.run {
            #expect(book.wordCount > 0, "Imported book had no words")
            #expect(!book.title.isEmpty)
        }
    }

    @Test(.enabled(if: OPDSLiveIntegrationTests.liveEnabled))
    func searchSurfacesResults() async throws {
        let server = makeServer()
        defer { teardown(server) }
        let client = OPDSClient()
        let searchURL = Self.liveURL.appending(path: "search/the")
        let feed = try await client.fetchFeed(url: searchURL, on: server)
        #expect(!feed.entries.isEmpty, "Search for 'the' returned no entries from a non-empty library")
    }

    @Test(.enabled(if: OPDSLiveIntegrationTests.liveEnabled))
    func testConnectionReturnsTrueAgainstLiveServer() async throws {
        let server = makeServer()
        defer { teardown(server) }
        let client = OPDSClient()
        let ok = try await client.testConnection(server)
        #expect(ok == true)
    }
}
