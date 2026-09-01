import Foundation
import Testing

/// iOS hermetic-lane network guard.
///
/// OBSERVED on iOS 26.5: global `URLProtocol.registerClass` covers `URLSession.shared`, but it does
/// not cover a session built from a custom configuration. Custom sessions therefore live in this
/// harness file and must include `HermeticNetworkGuardURLProtocol` in `protocolClasses`.
enum HermeticNetworkGuard {
    nonisolated(unsafe) private(set) static var isInstalled = false
    nonisolated(unsafe) private(set) static var blockedRequestCount = 0

    static func install() {
        // TDD scaffold: the red test proves the bundle-load installer cannot silently do nothing.
    }
}

final class HermeticNetworkGuardURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Issue.record("TDD scaffold reached instead of the implemented hermetic network guard")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

@_cdecl("SpeedReadInstallHermeticNetworkGuard")
func speedReadInstallHermeticNetworkGuard() {
    HermeticNetworkGuard.install()
}
