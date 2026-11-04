import Testing
import Foundation
@testable import SpeedRead

@Suite("RTF Extractor")
@MainActor
struct RTFExtractorTests {

    @Test func extractsPlainTextFromRTF() throws {
        // Minimal RTF document with plain ASCII content.
        let rtf = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\f0\\fs28 Hello, RTF reader!}"
        let data = Data(rtf.utf8)
        let result = try RTFExtractor().extractText(from: data)

        #expect(result.text.contains("Hello, RTF reader!"))
        #expect(result.chapters.isEmpty)
    }

    @Test func extractsMultipleParagraphs() throws {
        let rtf = "{\\rtf1\\ansi\\deff0 First paragraph.\\par Second paragraph.}"
        let data = Data(rtf.utf8)
        let result = try RTFExtractor().extractText(from: data)

        #expect(result.text.contains("First paragraph."))
        #expect(result.text.contains("Second paragraph."))
    }

    @Test func anEmbeddedPictureLeavesNoWordBehind() throws {
        let png = "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de0000000c49444154789c63f8cfc0000003010100c9fe92ef0000000049454e44ae426082"
        let rtf = "{\\rtf1\\ansi Before {\\pict\\pngblip\\picw1\\pich1\\picwgoal20\\pichgoal20 \(png)} after\\par}"
        let result = try RTFExtractor().extractText(from: Data(rtf.utf8))

        #expect(Book.tokenize(result.text) == ["Before", "after"])
    }

    @Test func invalidRTFThrows() {
        let extractor = RTFExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not an rtf doc".utf8))
        }
    }
}
