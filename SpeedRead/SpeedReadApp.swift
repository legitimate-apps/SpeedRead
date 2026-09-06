//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    @State private var themeManager = ThemeManager.shared

    static let modelTypes: [any PersistentModel.Type] = [
        Book.self, Bookmark.self, Highlight.self, OPDSServer.self
    ]

    init() {
        #if DEBUG
        // Clears the persisted flag so a UI test can watch onboarding COMPLETE. The
        // `-hasCompletedOnboarding NO` argument-domain shadow cannot do this: the argument domain
        // outranks the persistent one on read, so the write onboarding makes stays masked and the
        // app never advances. Reset the real value instead of shadowing it.
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environment(themeManager)
        }
        .modelContainer(for: Self.modelTypes)
    }
}
