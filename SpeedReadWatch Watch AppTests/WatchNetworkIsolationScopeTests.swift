import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

private final class WatchStubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Watch hermetic network scope", .serialized)
struct WatchNetworkIsolationScopeTests {
    @Test func watchMakesNoFalseGlobalRegistrationClaim() {
        #expect(!WatchNetworkIsolationScope.globalRegistrationCoversSharedSession)
    }

    @Test func explicitConfigurationInstallsStubThenBlockingFallback() async throws {
        let configuration = WatchNetworkIsolationScope.guardedConfiguration(
            protocolClasses: [WatchStubURLProtocol.self]
        )
        #expect(configuration.protocolClasses?.count == 2)
        #expect(configuration.protocolClasses?.first === WatchStubURLProtocol.self)
        #expect(configuration.protocolClasses?.last === WatchHermeticNetworkGuardURLProtocol.self)

        let session = WatchNetworkIsolationScope.guardedSession(
            protocolClasses: [WatchStubURLProtocol.self]
        )
        let (_, response) = try await session.data(
            from: URL(string: "https://speedread.invalid/stubbed")!
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 204)
    }
}
