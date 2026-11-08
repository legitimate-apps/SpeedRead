import Foundation
import Testing
@testable import SpeedRead

/// Browse, download, Test Connection and sync put `errorDescription` in front of the reader as it
/// is, so that is the string these tests read. "HTTP error 429." was what a reader saw when CWNG
/// paced their sign-in attempts.
@Suite("OPDS error messages")
struct OPDSErrorMessageTests {
    static let all: [OPDSError] = [
        .invalidURL, .insecureSchemeBlocked, .parseError, .cancelled,
        .networkError(URLError(.notConnectedToInternet).localizedDescription),
        .networkError("Non-HTTP response"), .deviceRemoved(nil),
        .deviceRemoved("This device was removed from the account, so it no longer syncs"),
    ] + [400, 401, 403, 404, 405, 409, 418, 429, 500, 502, 503].map { .httpError(status: $0) }

    @Test(arguments: all)
    func everyFailureReadsAsASentence(_ error: OPDSError) throws {
        let shown = try #require(error.errorDescription)
        #expect(shown == (error as Error).localizedDescription)
        #expect(shown.hasSuffix("."))
        #expect(shown.first?.isUppercase == true)
        #expect(!shown.contains("HTTP error"))
        #expect(!shown.hasPrefix("Network error:"))
        #expect(!shown.contains(".."))
    }

    @Test func tooManyAttemptsSaysToWaitAndTryAgain() throws {
        let shown = try #require(OPDSError.httpError(status: 429).errorDescription)
        #expect(shown.localizedCaseInsensitiveContains("too many"))
        #expect(shown.localizedCaseInsensitiveContains("try again"))
    }

    @Test func aRefusedPasswordNamesThePassword() throws {
        #expect(try #require(OPDSError.httpError(status: 401).errorDescription).contains("password"))
    }

    @Test func aTransportFailureKeepsTheSystemsReason() throws {
        let reason = URLError(.notConnectedToInternet).localizedDescription
        #expect(try #require(OPDSError.networkError(reason).errorDescription).contains(reason))
    }

    @Test func distinctStatusesDoNotCollapseIntoOneMessage() {
        let messages = Set([401, 403, 404, 429, 503].map { OPDSError.httpError(status: $0).errorDescription })
        #expect(messages.count == 5)
    }
}
