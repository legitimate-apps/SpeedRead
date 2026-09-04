struct ReviewPromptDecision: Equatable, Sendable {
    let shouldRequestReview: Bool
    let nextStoredLaunchCount: Int
}

enum ReviewPromptLogic {
    static let launchCountKey = "reviewPromptLaunchCount"

    private static let requestLaunchCount = 3
    private static let terminalLaunchCount = requestLaunchCount + 1

    static func decision(storedLaunchCount: Int) -> ReviewPromptDecision {
        guard storedLaunchCount < terminalLaunchCount else {
            return ReviewPromptDecision(
                shouldRequestReview: false,
                nextStoredLaunchCount: terminalLaunchCount
            )
        }

        let currentLaunchCount = max(0, storedLaunchCount)
        let thisLaunchCount = currentLaunchCount + 1
        return ReviewPromptDecision(
            shouldRequestReview: thisLaunchCount == requestLaunchCount,
            nextStoredLaunchCount: thisLaunchCount
        )
    }
}

@MainActor
final class ReviewPromptProcessGate {
    static let shared = ReviewPromptProcessGate()

    private var hasClaimedLaunch = false

    func claimLaunch() -> Bool {
        guard hasClaimedLaunch == false else { return false }
        hasClaimedLaunch = true
        return true
    }
}
