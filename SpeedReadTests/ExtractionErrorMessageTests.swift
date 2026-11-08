import Foundation
import Testing
@testable import SpeedRead

/// Both import paths put `localizedDescription` in front of the reader as it is, so that is
/// the string these tests read. Before ExtractionError was a LocalizedError it was
/// "The operation couldn't be completed. (SpeedRead.ExtractionError error 1.)".
@Suite("Extraction error messages")
struct ExtractionErrorMessageTests {
    static let all: [ExtractionError] = [
        .invalidData, .parsingFailed("Missing META-INF/container.xml"), .unsupportedFormat,
    ] + SupportedFormat.allCases.map { .noReadableText($0) }

    @Test(arguments: all)
    func everyFailureReadsAsASentenceForTheReader(_ error: ExtractionError) throws {
        let shown = (error as Error).localizedDescription
        #expect(shown == error.errorDescription)
        #expect(!shown.contains("ExtractionError"))
        #expect(!shown.contains("couldn’t be completed") && !shown.contains("couldn't be completed"))
        #expect(shown.hasSuffix("."))
    }

    /// The parser's detail is for logs; a reader cannot act on "OPF spine contains no chapters".
    @Test func aDamagedBookDoesNotShowTheParsersDetail() {
        let shown = (ExtractionError.parsingFailed("OPF spine contains no chapters") as Error).localizedDescription
        #expect(!shown.contains("OPF"))
    }

    @Test func aTextlessPDFSaysItIsProbablyAScan() {
        let shown = (ExtractionError.noReadableText(.pdf) as Error).localizedDescription
        #expect(shown.contains("PDF"))
        #expect(shown.contains("scan"))
        #expect((ExtractionError.noReadableText(.epub) as Error).localizedDescription != shown)
    }
}
