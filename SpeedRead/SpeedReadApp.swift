//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .onAppear { syncService.activate() }
        }
        .modelContainer(for: Book.self)
    }
}
