import Foundation
import Testing
@testable import SpeedRead

@Suite("Browse server view decisions")
@MainActor
struct BrowseServerLogicTests {
    @Test func routeDistinguishesEmptyPickerAutomaticAndSelectedServers() {
        let first = snapshot(name: "First", url: "https://first.example/opds")
        let second = snapshot(name: "Second", url: "https://second.example/opds")

        #expect(BrowseServerLogic.route(
            servers: [],
            selectedServerID: nil
        ) == .empty)
        #expect(BrowseServerLogic.route(
            servers: [first, second],
            selectedServerID: nil
        ) == .picker)
        #expect(BrowseServerLogic.route(
            servers: [first],
            selectedServerID: nil
        ) == .feed(.init(
            serverID: first.id,
            url: first.baseURL!,
            title: "First"
        )))
        #expect(BrowseServerLogic.route(
            servers: [first, second],
            selectedServerID: second.id
        ) == .feed(.init(
            serverID: second.id,
            url: second.baseURL!,
            title: "Second"
        )))
    }

    @Test func staleSelectionReturnsToPicker() {
        let server = snapshot(name: "Available", url: "https://books.example/opds")

        #expect(BrowseServerLogic.route(
            servers: [server, snapshot(name: "Other", url: "https://other.example/opds")],
            selectedServerID: UUID()
        ) == .picker)
    }

    @Test func invalidPersistedURLBecomesAnExplicitRouteInsteadOfAForceUnwrap() {
        let server = OPDSServer(
            name: "Broken",
            baseURL: URL(string: "https://books.example/opds")!,
            username: ""
        )
        server.baseURLString = "http://["
        let stored = BrowseServerLogic.ServerSnapshot(server: server)

        #expect(server.baseURL == nil)
        #expect(BrowseServerLogic.route(
            servers: [stored],
            selectedServerID: nil
        ) == .invalidURL(serverName: "Broken"))

        server.baseURLString = "relative/path"
        #expect(server.baseURL != nil)
        #expect(BrowseServerLogic.route(
            servers: [.init(server: server)],
            selectedServerID: nil
        ) == .invalidURL(serverName: "Broken"))
    }

    @Test func feedPresentationPreservesRefreshContentAndInitialLoadingRules() {
        #expect(BrowseServerLogic.feedPresentation(
            loading: true,
            hasFeed: false,
            error: nil
        ) == .loading)
        #expect(BrowseServerLogic.feedPresentation(
            loading: true,
            hasFeed: true,
            error: nil
        ) == .content)
        #expect(BrowseServerLogic.feedPresentation(
            loading: false,
            hasFeed: false,
            error: "Offline"
        ) == .failure("Offline"))
    }

    @Test func paginationIsOffDuringSearchAndReflectsLoadingState() {
        let next = URL(string: "https://books.example/opds?page=2")!

        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: nil,
            searchText: "",
            loadingMore: false
        ) == .hidden)
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next,
            searchText: "query",
            loadingMore: false
        ) == .hidden)
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next,
            searchText: "",
            loadingMore: false
        ) == .loadMore)
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next,
            searchText: "",
            loadingMore: true
        ) == .loading)
    }

    @Test func aFailedPageShowsItsFailureUntilTheRetryStarts() {
        let next = URL(string: "https://books.example/opds?page=2")!
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next, searchText: "", loadingMore: false, loadMoreError: "Offline."
        ) == .failed("Offline."))
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next, searchText: "", loadingMore: true, loadMoreError: "Offline."
        ) == .loading)
        #expect(BrowseServerLogic.paginationPresentation(
            nextPageURL: next, searchText: "query", loadingMore: false, loadMoreError: "Offline."
        ) == .hidden)
    }

    @Test func completedDownloadToastTakesPrecedenceOverAnError() {
        #expect(BrowseServerLogic.toastPresentation(
            completedTitle: nil,
            error: nil
        ) == .none)
        #expect(BrowseServerLogic.toastPresentation(
            completedTitle: nil,
            error: "Failed"
        ) == .failure("Failed"))
        #expect(BrowseServerLogic.toastPresentation(
            completedTitle: "Dune",
            error: "Older failure"
        ) == .added("Dune"))
    }

    private func snapshot(name: String, url: String) -> BrowseServerLogic.ServerSnapshot {
        BrowseServerLogic.ServerSnapshot(server: OPDSServer(
            name: name,
            baseURL: URL(string: url)!,
            username: ""
        ))
    }
}
