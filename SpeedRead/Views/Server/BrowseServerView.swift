//  BrowseServerView.swift
import SwiftUI
import SwiftData

struct BrowseServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \OPDSServer.sortIndex) private var servers: [OPDSServer]

    @State private var selectedServer: OPDSServer?

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()
                if servers.isEmpty {
                    emptyState
                } else if let only = onlyServer {
                    BrowseFeedView(server: only, url: only.baseURL!, title: only.name)
                } else if let selectedServer {
                    BrowseFeedView(server: selectedServer, url: selectedServer.baseURL!, title: selectedServer.name)
                } else {
                    serverPicker
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

    private var onlyServer: OPDSServer? {
        servers.count == 1 ? servers.first : nil
    }

    private var serverPicker: some View {
        List {
            Section("Select a Library Server") {
                ForEach(servers) { server in
                    Button {
                        selectedServer = server
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
            if loading && feed == nil {
                ProgressView().controlSize(.large)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(Color.crimsonSoft)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.crimsonSoft)
                }
            } else {
                feedList
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: url) { await load() }
        .searchable(text: $searchText, prompt: "Search this server")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .overlay(alignment: .bottom) {
            if let downloadCompleteTitle {
                ToastView(icon: "checkmark.circle.fill", text: "Added \(downloadCompleteTitle)", color: Color.agedGold)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2.2))
                            self.downloadCompleteTitle = nil
                        }
                    }
            } else if let downloadError {
                ToastView(icon: "exclamationmark.triangle.fill", text: downloadError, color: Color.crimsonSoft)
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
                    if nextPageURL != nil && searchText.isEmpty {
                        HStack {
                            Spacer()
                            if loadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Load more") { Task { await loadMore() } }
                                    .foregroundStyle(Color.crimsonSoft)
                            }
                            Spacer()
                        }
                        .task {
                            if !loadingMore { await loadMore() }
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
