import Foundation
import Synchronization

/// iOS hermetic-lane network guard.
///
/// OBSERVED on iOS 26.5: global `URLProtocol.registerClass` covers `URLSession.shared`, but it does
/// not cover a session built from a custom configuration. Custom sessions therefore live in this
/// harness file and must include `HermeticNetworkGuardURLProtocol` in `protocolClasses`.
enum HermeticNetworkGuard {
    private struct State {
        var isInstalled = false
        var blockedRequestCount = 0
    }
    private static let state = Mutex(State())
    static var isInstalled: Bool { state.withLock { $0.isInstalled } }
    static var blockedRequestCount: Int { state.withLock { $0.blockedRequestCount } }

    static func install() {
        state.withLock {
            guard !$0.isInstalled else { return }
            $0.isInstalled = URLProtocol.registerClass(HermeticNetworkGuardURLProtocol.self)
        }
    }

    static func recordBlockedRequest(_ request: URLRequest, context: String) {
        state.withLock { $0.blockedRequestCount += 1 }
        fatalError(
            "Hermetic network isolation blocked an un-stubbed request "
                + "(\(context)): \(request.url?.absoluteString ?? "<missing URL>")"
        )
    }
}

// URLProtocol requires restating its unchecked conformance; this subclass adds no mutable state.
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

// URLProtocol owns instance callback state; the only added shared state is protected by a mutex.
nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data?)

    private static let handlerStorage = Mutex<Handler?>(nil)
    static var handler: Handler? {
        get { handlerStorage.withLock { $0 } }
        set { handlerStorage.withLock { $0 = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let id = request.value(forHTTPHeaderField: "X-SpeedRead-Mock-Script") {
            guard let script = MockRequestScript.registered(id) else {
                HermeticNetworkGuard.recordBlockedRequest(request, context: "unknown mock script")
                return
            }
            script.consume(request) { [self] result in
                switch result {
                case .success(let (response, data)):
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    if let data { client?.urlProtocol(self, didLoad: data) }
                    client?.urlProtocolDidFinishLoading(self)
                case .failure(let error):
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }
            return
        }
        let nextHandler = Self.handlerStorage.withLock { value in
            let handler = value
            value = nil
            return handler
        }
        guard let handler = nextHandler else {
            HermeticNetworkGuard.recordBlockedRequest(request, context: "mock session without a stub")
            return
        }
        // A handler is one request's stub, not ambient suite state. Consuming it prevents a later
        // test that forgot to stub from receiving a stale success response.
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func mockSession(script: MockRequestScript? = nil) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    // Custom configurations ignore global URLProtocol registration. The mock gets first refusal;
    // the blocking guard is the fallback if a future stub protocol declines a request.
    if let script {
        configuration.httpAdditionalHeaders = ["X-SpeedRead-Mock-Script": script.id]
    }
    configuration.protocolClasses = [
        MockURLProtocol.self,
        HermeticNetworkGuardURLProtocol.self
    ]
    return URLSession(configuration: configuration)
}

/// Finite, per-session scripts. Matching is by exact URL, with FIFO consumption for repeats.
/// Unknown URLs and exhausted queues use the same fatal guard as a missing single-shot stub.
nonisolated final class MockRequestScript: Sendable {
    typealias Reply = Result<(HTTPURLResponse, Data?), URLError>
    private struct Stub {
        let url: URL
        let reply: Reply
        let held: Bool
    }
    private static let registry = Mutex<[String: MockRequestScript]>([:])
    let id = UUID().uuidString
    private struct State {
        var stubs: [Stub] = []
        var requests: [URLRequest] = []
        var pending: [@Sendable () -> Void] = []
    }
    private let state = Mutex(State())

    init() {
        Self.registry.withLock { $0[id] = self }
    }

    static func registered(_ id: String) -> MockRequestScript? {
        registry.withLock { $0[id] }
    }

    func close() {
        release()
        Self.registry.withLock { $0[id] = nil }
    }

    var observed: [URLRequest] {
        state.withLock { $0.requests }
    }

    var remaining: Int {
        state.withLock { $0.stubs.count }
    }

    func enqueue(_ url: URL, data: Data = Data(), status: Int = 200,
                 headers: [String: String]? = nil, held: Bool = false) {
        append(url, reply: .success((HTTPURLResponse(url: url, statusCode: status,
                    httpVersion: nil, headerFields: headers)!, data)), held: held)
    }

    func fail(_ url: URL, code: URLError.Code = .notConnectedToInternet, held: Bool = false) {
        append(url, reply: .failure(URLError(code)), held: held)
    }

    private func append(_ url: URL, reply: Reply, held: Bool) {
        state.withLock { $0.stubs.append(Stub(url: url, reply: reply, held: held)) }
    }

    func consume(_ request: URLRequest, deliver: @escaping @Sendable (Reply) -> Void) {
        let stub = state.withLock { state -> Stub? in
            state.requests.append(request)
            guard let index = state.stubs.firstIndex(where: { $0.url == request.url }) else {
                return nil
            }
            let stub = state.stubs.remove(at: index)
            if stub.held { state.pending.append { deliver(stub.reply) } }
            return stub
        }
        guard let stub else {
            HermeticNetworkGuard.recordBlockedRequest(request, context: "exhausted or unmatched mock script")
            return
        }
        if !stub.held { deliver(stub.reply) }
    }

    func release() {
        let deliveries = state.withLock { state in
            let deliveries = state.pending
            state.pending.removeAll()
            return deliveries
        }
        deliveries.forEach { $0() }
    }
}
