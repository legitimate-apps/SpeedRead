import Testing
import Foundation
import SwiftData
@testable import SpeedRead

/// End-to-end integration tests against the live CWNG instance on my server.
///
/// Every test in this suite is `.enabled(if: SPEEDREAD_LIVE_OPDS == "1")`, so
/// routine `xcodebuild test` runs skip them automatically. To exercise them
/// against the live server:
///
///     xcodebuild test ... \
///       -only-testing:SpeedReadTests/OPDSLiveIntegrationTests \
///       SPEEDREAD_LIVE_OPDS=1
///
/// Pre-conditions:
///   - my server is online at https://books.example.com
///   - the read-only `speedread-test` user exists in the CWNG `user` table
@Suite("OPDS Live Integration (my server)", .serialized)
struct OPDSLiveIntegrationTests {
    private static let liveURL = URL(string: "https://books.example.com/opds/")!
    private static let username = "speedread-test"
    private static let password = "not-a-real-password"

    private static let liveEnabled =
        ProcessInfo.processInfo.environment["SPEEDREAD_LIVE_OPDS"] == "1"

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
        let searchURL = URL(string: "https://books.example.com/opds/search/the")!
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
