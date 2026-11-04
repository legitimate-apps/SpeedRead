import Foundation
import Testing
@testable import SpeedRead

/// Until 2026-10-03 every count here included each spine document's head title, and every book's
/// first word was `"Cover"`, the cover page's <title>. The removed words (13, 46 and 34) were
/// counted independently from the EPUBs with a separate script, not taken from the extractor.
@Suite("Bundled Sample Book Tests")
@MainActor
struct BundledSampleBookTests {
    @Test func yellowWallpaperEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "TheYellowWallpaper")

        #expect(result.title == "The Yellow Wallpaper")
        #expect(result.author == "Charlotte Perkins Gilman")
        #expect(result.text.count == 50_822)
        #expect(words.count == 9_160)
        #expect(words.first == "The")
        #expect(words.last == "eBooks.")
    }

    @Test func metamorphosisEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "TheMetamorphosis")

        #expect(result.title == "Metamorphosis")
        #expect(result.author == "Franz Kafka")
        #expect(result.text.count == 138_272)
        #expect(words.count == 25_107)
        #expect(words.first == "The")
        #expect(words.last == "eBooks.")
    }

    @Test func christmasCarolEPUBContentIsPinned() throws {
        let (result, words) = try extractEPUB(named: "AChristmasCarol")

        #expect(result.title == "A Christmas Carol in Prose; Being a Ghost Story of Christmas")
        #expect(result.author == "Charles Dickens")
        #expect(result.text.count == 205_989)
        #expect(words.count == 32_002)
        #expect(words.first == "The")
        #expect(words.last == "eBooks.")
    }

    /// On OS 27 PDFKit reads this page's first two lines the other way round, so the first word
    /// depends on the OS. Everything else here doesn't. ChapterTokenIdentityTests holds the words
    /// themselves equal across OS versions.
    @Test func christmasCarolPDFContentIsPinned() throws {
        let url = try #require(Bundle.main.url(forResource: "AChristmasCarol", withExtension: "pdf"))
        let result = try PDFExtractor().extractText(from: Data(contentsOf: url))
        let words = Book.tokenize(result.text)

        #expect(result.text.count == 1_102)
        #expect(result.text.contains("Total Running Time: 03:14:22."))
        #expect(result.text.contains("Cover illustration by John Leech (1843)."))
        #expect(words.count == 187)
        if #available(iOS 27, *) {
            #expect(words.first == "Picture")
        } else {
            #expect(words.first == "A")
        }
        #expect(words.last == "Dickens")
    }

    private func extractEPUB(named name: String) throws -> (ExtractionResult, [String]) {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        let result = try EPUBExtractor().extractText(from: Data(contentsOf: url))
        return (result, Book.tokenize(result.text))
    }
}
