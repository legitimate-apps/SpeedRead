import Testing
import Foundation
@testable import SpeedRead

@Suite("RTF Extractor")
struct RTFExtractorTests {

    @Test func extractsPlainTextFromRTF() throws {
        // Minimal RTF document with plain ASCII content.
        let rtf = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\f0\\fs28 Hello, RTF reader!}"
        let data = Data(rtf.utf8)
        let result = try RTFExtractor().extractText(from: data)

        #expect(result.text.contains("Hello, RTF reader!"))
    }

    @Test func extractsMultipleParagraphs() throws {
        let rtf = "{\\rtf1\\ansi\\deff0 First paragraph.\\par Second paragraph.}"
        let data = Data(rtf.utf8)
        let result = try RTFExtractor().extractText(from: data)

        #expect(result.text.contains("First paragraph."))
        #expect(result.text.contains("Second paragraph."))
    }

    @Test func invalidRTFThrows() {
        let extractor = RTFExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not an rtf doc".utf8))
        }
    }
}
