//  ContentView.swift
import SwiftUI
import SwiftData
import StoreKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ReviewPromptLogic.launchCountKey) private var reviewPromptLaunchCount = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
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
        .onAppear {
            handleReviewPrompt()
        }
    }

    private func handleReviewPrompt() {
        guard ReviewPromptProcessGate.shared.claimLaunch() else { return }

        let decision = ReviewPromptLogic.decision(
            storedLaunchCount: reviewPromptLaunchCount
        )
        reviewPromptLaunchCount = decision.nextStoredLaunchCount
        if decision.shouldRequestReview {
            requestReview()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
        .environmentObject(WatchSyncService.shared)
}
