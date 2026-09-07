import Testing
@testable import SpeedRead

@Suite("Third-launch review prompt logic")
@MainActor
struct ReviewPromptLogicTests {
    @Test("Launch two does not request a review")
    func launchTwoDoesNotRequestAReview() {
        let decision = ReviewPromptLogic.decision(storedLaunchCount: 1)

        #expect(decision.shouldRequestReview == false)
        #expect(decision.nextStoredLaunchCount == 2)
    }

    @Test("Launch three requests a review")
    func launchThreeRequestsAReview() {
        let decision = ReviewPromptLogic.decision(storedLaunchCount: 2)

        #expect(decision.shouldRequestReview)
        #expect(decision.nextStoredLaunchCount == 3)
    }

    @Test("Launch four does not request another review")
    func launchFourDoesNotRequestAnotherReview() {
        let decision = ReviewPromptLogic.decision(storedLaunchCount: 3)

        #expect(decision.shouldRequestReview == false)
        #expect(decision.nextStoredLaunchCount == 4)
    }

    @Test("Stored count stops growing after the request boundary")
    func storedCountStopsGrowingAfterTheRequestBoundary() {
        #expect(
            ReviewPromptLogic.decision(storedLaunchCount: 4).nextStoredLaunchCount == 4
        )
        #expect(
            ReviewPromptLogic.decision(storedLaunchCount: 99).nextStoredLaunchCount == 4
        )
    }

    @Test("A process gate admits exactly one root appearance")
    @MainActor
    func processGateAdmitsExactlyOneRootAppearance() {
        let gate = ReviewPromptProcessGate()

        #expect(gate.claimLaunch())
        #expect(gate.claimLaunch() == false)
    }
}
