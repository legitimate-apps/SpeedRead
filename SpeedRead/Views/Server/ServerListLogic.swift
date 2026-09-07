//  ServerListLogic.swift
//  Decisions and deletion effects behind ServerListView.swift. Kept in its own file deliberately.
//
//  Attributable coverage is measured per FILE. A tested type sharing a file with SwiftUI
//  body markup pulls every one of those untested lines into the denominator, so the
//  metric reports worse the more logic you extract -- which is exactly backwards.
//  MEASURED 2026-09-01 with this type inline: ServerListView.swift read 160/241 (66.39%), contributing
//  241 lines to 'attributable'. The two logic types that already lived in their own
//  files read 97.50% and 100.00%. Same tests, same code, different file boundary.
import Foundation
import SwiftData

struct ServerListLogic {
    @MainActor
    static func deleteServers(at offsets: IndexSet, from servers: [OPDSServer], modelContext: ModelContext) {
        for server in serversToDelete(at: offsets, from: servers) {
            try? KeychainStore.deletePassword(for: server.keychainTag)
            modelContext.delete(server)
        }
        try? modelContext.save()
    }

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
