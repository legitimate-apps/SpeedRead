//  ServerListView.swift
import SwiftUI
import SwiftData

struct ServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \OPDSServer.sortIndex) private var servers: [OPDSServer]

    @State private var showingNewServer = false

    var body: some View {
        ZStack {
            Color.appSurface.ignoresSafeArea()
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
                .listRowBackground(Color.appSurfaceRaised)
            }
        }
        .navigationTitle("Library Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewServer = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .sheet(isPresented: $showingNewServer) {
            NavigationStack {
                ServerEditView(server: nil)
            }
        }
        .task {
            #if DEBUG
            // Screenshot hook: open the new-server editor without driving the plus button.
            if ProcessInfo.processInfo.arguments.contains("--auto-open-server-edit") {
                try? await Task.sleep(for: .milliseconds(600))
                showingNewServer = true
            }
            #endif
        }
    }

    private func serverRow(_ server: OPDSServer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name)
                .font(.headline)
                .foregroundStyle(Color.appInk)
            Text(server.baseURLString)
                .font(.caption)
                .foregroundStyle(Color.appInkSecondary)
                .lineLimit(1)
            Text(ServerListLogic.accountDetail(username: server.username))
                .font(.caption2)
                .foregroundStyle(Color.appInkSecondary)
            if let problem = ServerPositionSync.shared.problem(for: server.id) {
                Text(problem.message)
                    .font(.caption2)
                    .foregroundStyle(Color.appError)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.appInkSecondary)
            Text("No Library Servers")
                .font(.displayFont(size: 22, weight: .regular))
                .foregroundStyle(Color.appInk)
            Text("Add a server URL to browse books from your Calibre, Calibre-Web, or any other OPDS catalog.")
                .font(.bodySerif(size: 15))
                .foregroundStyle(Color.appInkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingNewServer = true
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.appOnAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.appAccent, in: Capsule())
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private func deleteServers(at offsets: IndexSet) {
        ServerListLogic.deleteServers(at: offsets, from: servers, modelContext: modelContext)
    }
}
