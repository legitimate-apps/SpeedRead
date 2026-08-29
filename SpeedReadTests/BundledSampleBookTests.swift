import Foundation
import Testing
@testable import SpeedRead

@Suite("Bundled Sample Book Tests")
struct BundledSampleBookTests {
    @Test func yellowWallpaperEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "TheYellowWallpaper")

        #expect(result.title == "The Yellow Wallpaper")
        #expect(result.author == "Charlotte Perkins Gilman")
        #expect(result.text.count == 50_913)
        #expect(words.count == 9_173)
        #expect(words.first == "\"Cover\"")
        #expect(words.last == "eBooks.")
    }

    @Test func metamorphosisEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "TheMetamorphosis")

        #expect(result.title == "Metamorphosis")
        #expect(result.author == "Franz Kafka")
        #expect(result.text.count == 138_589)
        #expect(words.count == 25_153)
        #expect(words.first == "\"Cover\"")
        #expect(words.last == "eBooks.")
    }

    @Test func christmasCarolEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "AChristmasCarol")

        #expect(result.title == "A Christmas Carol in Prose; Being a Ghost Story of Christmas")
        #expect(result.author == "Charles Dickens")
        #expect(result.text.count == 206_206)
        #expect(words.count == 32_036)
        #expect(words.first == "\"Cover\"")
        #expect(words.last == "eBooks.")
    }

    @Test func christmasCarolPDFContentIsPinned() throws {
        let url = try #require(Bundle.main.url(forResource: "AChristmasCarol", withExtension: "pdf"))
        let result = try PDFExtractor().extractText(from: Data(contentsOf: url))
        let words = Book.tokenize(result.text)

        #expect(result.text.count == 1_102)
        #expect(result.text.contains("Total Running Time: 03:14:22."))
        #expect(result.text.contains("Cover illustration by John Leech (1843)."))
        #expect(words.count == 187)
        #expect(words.first == "A")
        #expect(words.last == "Dickens")
    }

    private func extractEPUB(named name: String) throws -> (ExtractionResult, [String]) {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        let result = try EPUBExtractor().extractText(from: Data(contentsOf: url))
        return (result, Book.tokenize(result.text))
    }
}
