import Foundation
import Testing
@testable import SpeedRead

@Suite("Hermetic network isolation", .serialized)
struct NetworkIsolationGuardTests {
    @Test func globalGuardIsInstalledBeforeTestsExecute() {
        #expect(HermeticNetworkGuard.isInstalled)
    }

    @Test func unStubbedRequestPositiveControl() async {
        guard ProcessInfo.processInfo.environment[
            "SPEEDREAD_NETWORK_GUARD_POSITIVE_CONTROL"
        ] == "1" else {
            #expect(HermeticNetworkGuard.isInstalled)
            return
        }

        let countBeforeRequest = HermeticNetworkGuard.blockedRequestCount
        do {
            _ = try await URLSession.shared.data(
                from: URL(string: "https://speedread.invalid/positive-control")!
            )
            Issue.record("positive-control request unexpectedly succeeded")
        } catch {
            // The guard records an Issue before failing the URL load. The count distinguishes that
            // failure from a DNS/offline error after a real request escaped interception.
        }
        #expect(HermeticNetworkGuard.blockedRequestCount == countBeforeRequest + 1)
    }
}
