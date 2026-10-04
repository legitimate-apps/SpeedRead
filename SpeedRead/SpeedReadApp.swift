//  SpeedReadApp.swift
import SwiftUI
import SwiftData
import UIKit

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    @State private var themeManager = ThemeManager.shared

    static let modelTypes: [any PersistentModel.Type] = [
        Book.self, Bookmark.self, Highlight.self, OPDSServer.self
    ]

    init() {
        // Serif nav titles, one place: every sheet and pushed screen inherits the
        // reading-room voice instead of system sans. Colors stay with each surface's
        // toolbarColorScheme.
        let largeTitle = UIFont.systemFont(ofSize: 34, weight: .bold)
        let inlineTitle = UIFont.systemFont(ofSize: 17, weight: .semibold)
        if let serifLarge = largeTitle.fontDescriptor.withDesign(.serif).map({ UIFont(descriptor: $0, size: 34) }),
           let serifInline = inlineTitle.fontDescriptor.withDesign(.serif).map({ UIFont(descriptor: $0, size: 17) }) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: serifLarge]
            UINavigationBar.appearance().titleTextAttributes = [.font: serifInline]
        }

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
