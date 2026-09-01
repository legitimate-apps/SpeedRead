import Foundation

/// iOS hermetic-lane network guard.
///
/// OBSERVED on iOS 26.5: global `URLProtocol.registerClass` covers `URLSession.shared`, but it does
/// not cover a session built from a custom configuration. Custom sessions therefore live in this
/// harness file and must include `HermeticNetworkGuardURLProtocol` in `protocolClasses`.
enum HermeticNetworkGuard {
    nonisolated(unsafe) private(set) static var isInstalled = false
    nonisolated(unsafe) private(set) static var blockedRequestCount = 0
    private static let lock = NSLock()

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !isInstalled else { return }
        isInstalled = URLProtocol.registerClass(HermeticNetworkGuardURLProtocol.self)
    }

    static func recordBlockedRequest(_ request: URLRequest, context: String) {
        lock.lock()
        blockedRequestCount += 1
        lock.unlock()
        fatalError(
            "Hermetic network isolation blocked an un-stubbed request "
                + "(\(context)): \(request.url?.absoluteString ?? "<missing URL>")"
        )
    }
}

final class HermeticNetworkGuardURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "http" || request.url?.scheme == "https"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        HermeticNetworkGuard.recordBlockedRequest(request, context: "global/default session")
    }

    override func stopLoading() {}
}

@_cdecl("SpeedReadInstallHermeticNetworkGuard")
func speedReadInstallHermeticNetworkGuard() {
    HermeticNetworkGuard.install()
}

nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) -> (HTTPURLResponse, Data?)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            HermeticNetworkGuard.recordBlockedRequest(request, context: "mock session without a stub")
            return
        }
        // A handler is one request's stub, not ambient suite state. Consuming it prevents a later
        // test that forgot to stub from receiving a stale success response.
        Self.handler = nil
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func mockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    // Custom configurations ignore global URLProtocol registration. The mock gets first refusal;
    // the blocking guard is the fallback if a future stub protocol declines a request.
    configuration.protocolClasses = [
        MockURLProtocol.self,
        HermeticNetworkGuardURLProtocol.self
    ]
    return URLSession(configuration: configuration)
}
