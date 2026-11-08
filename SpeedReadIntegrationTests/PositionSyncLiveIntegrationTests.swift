import Foundation
import Testing
@testable import SpeedRead

/// Two devices' places through a live CWNG server, decided by when each reader was there.
///
/// Enabled by the same variables as the annotation suite (the book id is the server's id for any
/// book; the push uses it as the KOSync document):
///
///     SPEEDREAD_LIVE_OPDS=1 SPEEDREAD_TEST_OPDS_URL=http://127.0.0.1:18086/opds/ \
///     SPEEDREAD_TEST_OPDS_USER=... SPEEDREAD_TEST_OPDS_PASSWORD=... \
///     SPEEDREAD_TEST_ANNOTATION_BOOK_ID=221 \
///     xcodebuild test ... -testPlan Integration
///
/// The two device ids are fixed, so CWNG registers them once. While CWNG gates places, a new
/// device keeps its place private: tick Share my place for both ("SpeedRead live A" and
/// "SpeedRead live B" in Account → Devices) after the first run, or the read-back sees neither.
@Suite("Position sync live", .serialized)
@MainActor
struct PositionSyncLiveIntegrationTests {
    nonisolated private static let env = ProcessInfo.processInfo.environment
    nonisolated private static let liveURL =
        URL(string: env["SPEEDREAD_TEST_OPDS_URL"] ?? "") ?? URL(string: "https://unconfigured.invalid/opds/")!
    nonisolated private static let username = env["SPEEDREAD_TEST_OPDS_USER"] ?? ""
    nonisolated private static let password = env["SPEEDREAD_TEST_OPDS_PASSWORD"] ?? ""
    nonisolated private static let bookID = env["SPEEDREAD_TEST_ANNOTATION_BOOK_ID"] ?? ""

    nonisolated private static let liveEnabled =
        env["SPEEDREAD_LIVE_OPDS"] == "1"
        && !(env["SPEEDREAD_TEST_OPDS_URL"] ?? "").isEmpty
        && !username.isEmpty && !password.isEmpty && !bookID.isEmpty

    /// A reads further, then B reads an earlier page more recently. Furthest-wins would keep A's
    /// 0.30; the server must keep B's 0.20, because B was there last.
    @Test(.enabled(if: PositionSyncLiveIntegrationTests.liveEnabled))
    func theLaterReaderWinsEvenFromAnEarlierPage() async throws {
        let server = OPDSServer(name: "live-place", baseURL: Self.liveURL, username: Self.username,
                                allowInsecureHTTP: Self.liveURL.scheme == "http")
        try KeychainStore.setPassword(Self.password, for: server.keychainTag)
        defer { try? KeychainStore.deletePassword(for: server.keychainTag) }
        let configuration = OPDSRequestConfiguration(server)
        let a = KOSyncDevice(id: "speedread-live-place-a", name: "SpeedRead live A")
        let b = KOSyncDevice(id: "speedread-live-place-b", name: "SpeedRead live B")
        let now = Date()

        let clientA = KOSyncClient().identified(as: a), clientB = KOSyncClient().identified(as: b)
        #expect(try await clientA.support(of: configuration) == .anchorPositions)
        try await clientA.push(KOSyncPush(document: Self.bookID, percentage: 0.30, device: a.name, deviceID: a.id,
                                          anchor: nil, timestamp: KOSyncWire.clientClock(now.addingTimeInterval(-60), now: now)),
                               to: configuration)
        try await clientB.push(KOSyncPush(document: Self.bookID, percentage: 0.20, device: b.name, deviceID: b.id,
                                          anchor: nil, timestamp: KOSyncWire.clientClock(Date(), now: Date())),
                               to: configuration)

        // Read as no device in particular: the account's shared place.
        let winner = try #require(try await KOSyncClient().position(of: Self.bookID, on: configuration))
        #expect(winner.deviceID == b.id, "is Share my place on for both live devices?")
        #expect(abs(winner.percentage - 0.20) < 0.0001)
    }
}
