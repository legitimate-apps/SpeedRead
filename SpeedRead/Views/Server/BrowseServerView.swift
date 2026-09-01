//  BrowseServerView.swift
import SwiftUI
import SwiftData

struct BrowseServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \OPDSServer.sortIndex) private var servers: [OPDSServer]

    @State private var selectedServerID: UUID?

    private var route: BrowseServerLogic.Route {
        BrowseServerLogic.route(
            servers: servers.map(BrowseServerLogic.ServerSnapshot.init),
            selectedServerID: selectedServerID
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()
                switch route {
                case .empty:
                    emptyState
                case .picker:
                    serverPicker
                case .feed(let destination):
                    if let server = servers.first(where: { $0.id == destination.serverID }) {
                        BrowseFeedView(
                            server: server,
                            url: destination.url,
                            title: destination.title
                        )
                    } else {
                        serverPicker
                    }
                case .invalidURL(let serverName):
                    invalidServerState(serverName: serverName)
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.crimsonSoft)
                }
            }
        }
    }

    private var serverPicker: some View {
        List {
            Section("Select a Library Server") {
                ForEach(servers) { server in
                    Button {
                        selectedServerID = server.id
                        server.lastUsedAt = Date()
                        try? modelContext.save()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(server.name)
                                    .font(.headline)
                                    .foregroundStyle(Color.walnut)
                                Text(server.baseURLString)
                                    .font(.caption)
                                    .foregroundStyle(Color.walnutLight)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.walnutLight)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.walnutLight)
            Text("No Library Servers")
                .font(.displayFont(size: 22, weight: .regular))
                .foregroundStyle(Color.walnut)
            Text("Open Settings to add an OPDS server.")
                .font(.system(size: 14))
                .foregroundStyle(Color.walnutLight)
        }
        .padding()
    }

    private func invalidServerState(serverName: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.crimsonSoft)
            Text("Invalid Server URL")
                .font(.displayFont(size: 22, weight: .regular))
                .foregroundStyle(Color.walnut)
            Text("The saved URL for \(serverName) is invalid. Open Settings to correct it.")
                .font(.system(size: 14))
                .foregroundStyle(Color.walnutLight)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct BrowseFeedView: View {
    let server: OPDSServer
    let url: URL
    let title: String

    @Environment(\.modelContext) private var modelContext

    @State private var feed: OPDSFeed?
    @State private var nextPageURL: URL?
    @State private var paginatedEntries: [OPDSEntry] = []
    @State private var loadingMore = false
    @State private var loading = true
    @State private var error: String?
    @State private var searchText: String = ""
    @State private var searchedFeed: OPDSFeed?
    @State private var downloadingEntryID: String?
    @State private var downloadError: String?
    @State private var downloadCompleteTitle: String?

    private var displayEntries: [OPDSEntry] {
        OPDSBrowseLogic.displayEntries(
            searchText: searchText,
            searchedFeed: searchedFeed,
            paginatedEntries: paginatedEntries
        )
    }

    private var entrySections: OPDSBrowseLogic.EntrySections {
        OPDSBrowseLogic.sections(for: displayEntries)
    }

    private var navigationLinks: [OPDSEntry] { entrySections.navigation }

    private var bookEntries: [OPDSEntry] { entrySections.books }

    var body: some View {
        Group {
            switch BrowseServerLogic.feedPresentation(
                loading: loading,
                hasFeed: feed != nil,
                error: error
            ) {
            case .loading:
                ProgressView().controlSize(.large)
            case .failure(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(Color.crimsonSoft)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.crimsonSoft)
                }
            case .content:
                feedList
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: url) { await load() }
        .searchable(text: $searchText, prompt: "Search this server")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .overlay(alignment: .bottom) {
            switch BrowseServerLogic.toastPresentation(
                completedTitle: downloadCompleteTitle,
                error: downloadError
            ) {
            case .none:
                EmptyView()
            case .added(let title):
                ToastView(icon: "checkmark.circle.fill", text: "Added \(title)", color: Color.agedGold)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2.2))
                            self.downloadCompleteTitle = nil
                        }
                    }
            case .failure(let message):
                ToastView(icon: "exclamationmark.triangle.fill", text: message, color: Color.crimsonSoft)
                    .onTapGesture { self.downloadError = nil }
            }
        }
    }

    private var feedList: some View {
        List {
            if !navigationLinks.isEmpty {
                Section("Categories") {
                    ForEach(navigationLinks, id: \.id) { entry in
                        if let target = entry.navigationLink {
                            NavigationLink {
                                BrowseFeedView(server: server, url: target, title: entry.title)
                            } label: {
                                Label(entry.title, systemImage: "folder")
                                    .foregroundStyle(Color.walnut)
                            }
                        }
                    }
                }
            }
            if !bookEntries.isEmpty {
                Section("Books") {
                    ForEach(bookEntries, id: \.id) { entry in
                        NavigationLink {
                            RemoteBookDetailView(
                                server: server,
                                entry: entry,
                                onAdded: { title in downloadCompleteTitle = title }
                            )
                        } label: {
                            OPDSEntryRowView(entry: entry) { url in
                                await fetchCover(url: url)
                            }
                        }
                    }
                    let pagination = BrowseServerLogic.paginationPresentation(
                        nextPageURL: nextPageURL,
                        searchText: searchText,
                        loadingMore: loadingMore
                    )
                    if pagination != .hidden {
                        HStack {
                            Spacer()
                            switch pagination {
                            case .loading:
                                ProgressView().controlSize(.small)
                            case .loadMore:
                                Button("Load more") { Task { await loadMore() } }
                                    .foregroundStyle(Color.crimsonSoft)
                            case .hidden:
                                EmptyView()
                            }
                            Spacer()
                        }
                        .task {
                            if pagination == .loadMore { await loadMore() }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        let client = OPDSClient()
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

    private func loadMore() async {
        guard let next = nextPageURL, !loadingMore else { return }
        loadingMore = true
        let client = OPDSClient()
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

    private func runSearch() async {
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
        let client = OPDSClient()
        do {
            searchedFeed = try await client.fetchFeed(url: searchURL, on: server)
        } catch {
            searchedFeed = nil
            self.error = (error as? OPDSError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchCover(url: URL) async -> Image? {
        if let cached = OPDSCoverCache.shared.image(for: url) {
            return cached
        }
        let client = OPDSClient()
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

private struct ToastView: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
