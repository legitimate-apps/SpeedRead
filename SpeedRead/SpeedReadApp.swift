//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environment(themeManager)
                .onAppear { syncService.activate() }
        }
        .modelContainer(for: [Book.self, Bookmark.self, Highlight.self, OPDSServer.self])
    }
}
