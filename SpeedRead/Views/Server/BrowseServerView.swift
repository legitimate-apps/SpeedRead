//  BrowseServerView.swift
import SwiftUI
import SwiftData

struct BrowseServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \OPDSServer.sortIndex) private var servers: [OPDSServer]

    @State private var session: BrowseServerSession

    init(session: BrowseServerSession? = nil) {
        _session = State(initialValue: session ?? BrowseServerSession())
    }

    private var route: BrowseServerLogic.Route {
        BrowseServerLogic.route(
            servers: servers.map(BrowseServerLogic.ServerSnapshot.init),
            selectedServerID: session.selectedServerID
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
                            title: destination.title,
                            session: session
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
                        session.selectServer(server.id, servers: servers, modelContext: modelContext)
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
    @State private var session: BrowseServerSession

    init(server: OPDSServer, url: URL, title: String, session: BrowseServerSession? = nil) {
        self.server = server
        self.url = url
        self.title = title
        _session = State(initialValue: session ?? BrowseServerSession())
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.opdsClientFactory) private var makeClient

    private var entrySections: OPDSBrowseLogic.EntrySections {
        OPDSBrowseLogic.sections(for: session.displayEntries)
    }

    private var navigationLinks: [OPDSEntry] { entrySections.navigation }

    private var bookEntries: [OPDSEntry] { entrySections.books }

    var body: some View {
        Group {
            switch BrowseServerLogic.feedPresentation(
                loading: session.loading,
                hasFeed: session.feed != nil,
                error: session.error
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
                    Button("Retry") { Task { await session.load(url: url, on: server, modelContext: modelContext, makeClient: makeClient) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.crimsonSoft)
                }
            case .content:
                feedList
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: url) { await session.load(url: url, on: server, modelContext: modelContext, makeClient: makeClient) }
        .searchable(text: $session.searchText, prompt: "Search this server")
        .onSubmit(of: .search) { Task { await session.runSearch(on: server, makeClient: makeClient) } }
        .overlay(alignment: .bottom) {
            switch BrowseServerLogic.toastPresentation(
                completedTitle: session.downloadCompleteTitle,
                error: session.downloadError
            ) {
            case .none:
                EmptyView()
            case .added(let title):
                ToastView(icon: "checkmark.circle.fill", text: "Added \(title)", color: Color.agedGold)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2.2))
                            session.downloadCompleteTitle = nil
                        }
                    }
            case .failure(let message):
                ToastView(icon: "exclamationmark.triangle.fill", text: message, color: Color.crimsonSoft)
                    .onTapGesture { session.downloadError = nil }
            }
        }
    }

    private var feedList: some View {
        List {
            if !navigationLinks.isEmpty {
                Section("Browse") {
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
                                onAdded: { title in session.downloadCompleteTitle = title }
                            )
                        } label: {
                            OPDSEntryRowView(entry: entry) { url in
                                await session.fetchCover(url: url, on: server, makeClient: makeClient)
                            }
                        }
                    }
                    let pagination = BrowseServerLogic.paginationPresentation(
                        nextPageURL: session.nextPageURL,
                        searchText: session.searchText,
                        loadingMore: session.loadingMore
                    )
                    if pagination != .hidden {
                        HStack {
                            Spacer()
                            switch pagination {
                            case .loading:
                                ProgressView().controlSize(.small)
                            case .loadMore:
                                Button("Load more") { Task { await session.loadMore(on: server, makeClient: makeClient) } }
                                    .foregroundStyle(Color.crimsonSoft)
                            case .hidden:
                                EmptyView()
                            }
                            Spacer()
                        }
                    .task {
                            if pagination == .loadMore { await session.loadMore(on: server, makeClient: makeClient) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await session.load(url: url, on: server, modelContext: modelContext, makeClient: makeClient) }
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
