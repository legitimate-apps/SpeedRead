//  ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: WatchSyncService

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                LibraryView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .task {
            syncService.configure(modelContext: modelContext)
            syncService.activate()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
        .environmentObject(WatchSyncService.shared)
}
