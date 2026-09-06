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
nonisolated final class MockRequestScript: @unchecked Sendable {
    typealias Reply = Result<(HTTPURLResponse, Data?), URLError>
    private struct Stub {
        let url: URL
        let reply: Reply
        let held: Bool
    }
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: MockRequestScript] = [:]
    let id = UUID().uuidString
    private let lock = NSLock()
    private var stubs: [Stub] = []
    private var requests: [URLRequest] = []
    private var pending: [() -> Void] = []

    init() {
        Self.registryLock.lock()
        Self.registry[id] = self
        Self.registryLock.unlock()
    }

    static func registered(_ id: String) -> MockRequestScript? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return registry[id]
    }

    func close() {
        release()
        Self.registryLock.lock()
        Self.registry[id] = nil
        Self.registryLock.unlock()
    }

    var observed: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var remaining: Int {
        lock.lock()
        defer { lock.unlock() }
        return stubs.count
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
        lock.lock()
        stubs.append(Stub(url: url, reply: reply, held: held))
        lock.unlock()
    }

    func consume(_ request: URLRequest, deliver: @escaping (Reply) -> Void) {
        lock.lock()
        requests.append(request)
        guard let index = stubs.firstIndex(where: { $0.url == request.url }) else {
            lock.unlock()
            HermeticNetworkGuard.recordBlockedRequest(request, context: "exhausted or unmatched mock script")
            return
        }
        let stub = stubs.remove(at: index)
        if stub.held { pending.append { deliver(stub.reply) } }
        lock.unlock()
        if !stub.held { deliver(stub.reply) }
    }

    func release() {
        lock.lock()
        let deliveries = pending
        pending.removeAll()
        lock.unlock()
        deliveries.forEach { $0() }
    }
}
