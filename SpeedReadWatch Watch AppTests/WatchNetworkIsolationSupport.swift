import Foundation
import Testing

/// watchOS hermetic-lane scope.
///
/// OBSERVED on watchOS 26.5: a class placed directly in `configuration.protocolClasses` intercepts;
/// global `URLProtocol.registerClass` silently does not intercept `URLSession.shared`. This harness
/// therefore makes no global-coverage claim. The source audit forbids shared/custom sessions in the
/// watch trees outside this file, and this factory always appends the blocking fallback.
enum WatchNetworkIsolationScope {
    static let globalRegistrationCoversSharedSession = false

    static func guardedConfiguration(
        protocolClasses: [AnyClass] = []
    ) -> URLSessionConfiguration {
        // TDD scaffold: the red test proves explicit protocol classes are actually installed.
        .ephemeral
    }
}

final class WatchHermeticNetworkGuardURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "http" || request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Issue.record("watch hermetic lane blocked an un-stubbed request to \(request.url?.absoluteString ?? "<missing URL>")")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
