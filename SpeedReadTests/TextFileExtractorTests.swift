import Testing
import Foundation
@testable import SpeedRead

@Suite("Plain Text Extractor")
struct TextFileExtractorTests {

    @Test func extractsUTF8Text() throws {
        let body = "The Yellow Wallpaper\n\nIt is very seldom that mere ordinary people like John and myself secure ancestral halls."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)

        #expect(result.text.contains("ancestral halls"))
        #expect(result.title == "The Yellow Wallpaper")
    }

    @Test func parsesProjectGutenbergStyleTitle() throws {
        let body = "Title: A Christmas Carol\n\nMarley was dead: to begin with."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)

        #expect(result.title == "A Christmas Carol")
    }

    @Test func emptyStringThrows() {
        let extractor = TextFileExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data())
        }
    }

    @Test func normalizesCarriageReturns() throws {
        let body = "Heading\r\n\r\nLine one\rLine two"
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(!result.text.contains("\r"))
    }

    @Test func longFirstLineIsNotMistakenForTitle() throws {
        let body = String(repeating: "really long opening sentence ", count: 6) + "."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(result.title == nil)
    }

    @Test func chapterHeadingIsNotTitle() throws {
        let body = "CHAPTER ONE\n\nIt was the best of times, it was the worst of times."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(result.title == nil)
    }

    @Test func allCapsHeaderIsNotTitle() throws {
        let body = "PROLOGUE\n\nIn the beginning there were stories."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(result.title == nil)
    }

    @Test func gutenbergTitleHeaderTrumpsAllCaps() throws {
        let body = "Title: Pride and Prejudice\n\nCHAPTER 1\n\nIt is a truth universally acknowledged."
        let data = Data(body.utf8)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(result.title == "Pride and Prejudice")
    }

    @Test func fallsBackFromInvalidUTF8() throws {
        // Latin-1 encoded "café"
        let bytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9]
        let data = Data(bytes)
        let result = try TextFileExtractor().extractText(from: data)
        #expect(result.text.contains("caf"))
    }
}
