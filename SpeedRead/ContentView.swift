//  ContentView.swift
import SwiftUI
import SwiftData
import StoreKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(ReviewPromptLogic.launchCountKey) private var reviewPromptLaunchCount = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var syncService: WatchSyncService

    private let reviewPromptGate: ReviewPromptProcessGate
    private let reviewRequest: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         reviewPromptGate: ReviewPromptProcessGate = .shared,
         reviewRequest: (() -> Void)? = nil) {
        _hasCompletedOnboarding = AppStorage(wrappedValue: false, "hasCompletedOnboarding", store: defaults)
        _reviewPromptLaunchCount = AppStorage(wrappedValue: 0, ReviewPromptLogic.launchCountKey, store: defaults)
        self.reviewPromptGate = reviewPromptGate
        self.reviewRequest = reviewRequest
    }

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
            ServerPositionSync.shared.configure(modelContainer: modelContext.container)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // Leaving the app is the moment a place must reach the server: the next reader may
            // be picked up within seconds.
            ServerPositionSync.shared.flushInBackground()
        }
        .onAppear {
            handleReviewPrompt()
        }
    }

    private func handleReviewPrompt() {
        guard reviewPromptGate.claimLaunch() else { return }

        let decision = ReviewPromptLogic.decision(
            storedLaunchCount: reviewPromptLaunchCount
        )
        reviewPromptLaunchCount = decision.nextStoredLaunchCount
        if decision.shouldRequestReview {
            if let reviewRequest { reviewRequest() } else { requestReview() }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
        .environmentObject(WatchSyncService.shared)
}
