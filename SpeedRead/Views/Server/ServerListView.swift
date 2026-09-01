//  ServerListView.swift
import SwiftUI
import SwiftData

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \OPDSServer.sortIndex) private var servers: [OPDSServer]

    @State private var showingNewServer = false

    var body: some View {
        ZStack {
            themeManager.currentTheme.backgroundColor.ignoresSafeArea()
            if servers.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(servers) { server in
                            NavigationLink {
                                ServerEditView(server: server)
                            } label: {
                                serverRow(server)
                            }
                        }
                        .onDelete(perform: deleteServers)
                    } footer: {
                        Text("Browse a server from the cloud icon on the library screen.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Library Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewServer = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.crimsonSoft)
                }
            }
        }
        .sheet(isPresented: $showingNewServer) {
            NavigationStack {
                ServerEditView(server: nil)
            }
        }
    }

    private func serverRow(_ server: OPDSServer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name)
                .font(.headline)
                .foregroundStyle(Color.walnut)
            Text(server.baseURLString)
                .font(.caption)
                .foregroundStyle(Color.walnutLight)
                .lineLimit(1)
            Text(ServerListLogic.accountDetail(username: server.username))
                .font(.caption2)
                .foregroundStyle(Color.walnutLight)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.walnutLight)
            Text("No Library Servers")
                .font(.displayFont(size: 22, weight: .regular))
                .foregroundStyle(Color.walnut)
            Text("Add a server URL to browse books from your Calibre, Calibre-Web, or any other OPDS catalog.")
                .font(.system(size: 14))
                .foregroundStyle(Color.walnutLight)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingNewServer = true
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.parchment)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.crimsonSoft, in: Capsule())
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private func deleteServers(at offsets: IndexSet) {
        for server in ServerListLogic.serversToDelete(at: offsets, from: servers) {
            try? KeychainStore.deletePassword(for: server.keychainTag)
            modelContext.delete(server)
        }
        try? modelContext.save()
    }
}

struct ServerListLogic {
    static func accountDetail(username: String) -> String {
        username.isEmpty ? "anonymous" : "user: \(username)"
    }

    static func serversToDelete(
        at offsets: IndexSet,
        from displayedServers: [OPDSServer]
    ) -> [OPDSServer] {
        offsets.map { displayedServers[$0] }
    }
}
