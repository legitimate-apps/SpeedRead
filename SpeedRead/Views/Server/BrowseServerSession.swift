import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class BrowseServerSession {
    var selectedServerID: UUID?
    private(set) var feed: OPDSFeed?
    private(set) var nextPageURL: URL?
    private(set) var paginatedEntries: [OPDSEntry] = []
    private(set) var loadingMore = false
    private(set) var loading = true
    private(set) var error: String?
    var searchText: String = ""
    private(set) var searchedFeed: OPDSFeed?
    var downloadError: String?
    var downloadCompleteTitle: String?

    var displayEntries: [OPDSEntry] {
        OPDSBrowseLogic.displayEntries(
            searchText: searchText,
            searchedFeed: searchedFeed,
            paginatedEntries: paginatedEntries
        )
    }

    func selectServer(_ id: UUID, servers: [OPDSServer], modelContext: ModelContext) {
        guard let server = servers.first(where: { $0.id == id }) else { return }
        selectedServerID = server.id
        server.lastUsedAt = Date()
        try? modelContext.save()
    }

    func load(url: URL, on server: OPDSServer, modelContext: ModelContext, makeClient: () -> OPDSClient) async {
        loading = true
        error = nil
        let client = makeClient()
        do {
            let result = try await client.fetchFeed(url: url, on: server)
            self.feed = result
            self.paginatedEntries = result.entries
            self.nextPageURL = result.nextPageURL
            server.lastUsedAt = Date()
            try? modelContext.save()
        } catch let opdsError as OPDSError {
            self.error = opdsError.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func loadMore(on server: OPDSServer, makeClient: () -> OPDSClient) async {
        guard let next = nextPageURL, !loadingMore else { return }
        loadingMore = true
        let client = makeClient()
        do {
            let more = try await client.fetchFeed(url: next, on: server)
            self.paginatedEntries.append(contentsOf: more.entries)
            self.nextPageURL = more.nextPageURL
        } catch {
            // Don't blow up the whole view for pagination — just stop the spinner.
            self.nextPageURL = nil
        }
        loadingMore = false
    }

    func runSearch(on server: OPDSServer, makeClient: () -> OPDSClient) async {
        let action = OPDSBrowseLogic.searchAction(
            query: searchText,
            advertisedTemplate: feed?.searchTemplate,
            baseURL: server.baseURL
        )
        let searchURL: URL
        switch action {
        case .clear:
            searchedFeed = nil
            return
        case .unavailable:
            return
        case .fetch(let url):
            searchURL = url
        }
        let client = makeClient()
        do {
            searchedFeed = try await client.fetchFeed(url: searchURL, on: server)
        } catch {
            searchedFeed = nil
            self.error = (error as? OPDSError)?.errorDescription ?? error.localizedDescription
        }
    }

    func fetchCover(url: URL, on server: OPDSServer, makeClient: () -> OPDSClient) async -> Image? {
        if let cached = OPDSCoverCache.shared.image(for: url) {
            return cached
        }
        let client = makeClient()
        do {
            let payload = try await client.download(from: url, on: server)
            #if canImport(UIKit)
            if let ui = UIImage(data: payload.data) {
                let image = Image(uiImage: ui)
                OPDSCoverCache.shared.store(image, for: url)
                return image
            }
            #endif
            return nil
        } catch {
            return nil
        }
    }
}
