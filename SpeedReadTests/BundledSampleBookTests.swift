import Foundation
import Testing
@testable import SpeedRead

@Suite("Bundled Sample Book Tests")
struct BundledSampleBookTests {
    @Test func yellowWallpaperEPUBContentIsPinned() throws {
        try expectEPUB(
            name: "TheYellowWallpaper",
            title: "The Yellow Wallpaper",
            author: "Charlotte Perkins Gilman",
            characterCount: 50_913,
            wordCount: 9_173,
            firstWord: "\"Cover\"",
            lastWord: "eBooks."
        )
    }

    @Test func metamorphosisEPUBContentIsPinned() throws {
        try expectEPUB(
            name: "TheMetamorphosis",
            title: "Metamorphosis",
            author: "Franz Kafka",
            characterCount: 138_589,
            wordCount: 25_153,
            firstWord: "\"Cover\"",
            lastWord: "eBooks."
        )
    }

    @Test func christmasCarolEPUBContentIsPinned() throws {
        try expectEPUB(
            name: "AChristmasCarol",
            title: "A Christmas Carol in Prose; Being a Ghost Story of Christmas",
            author: "Charles Dickens",
            characterCount: 206_206,
            wordCount: 32_036,
            firstWord: "\"Cover\"",
            lastWord: "eBooks."
        )
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

    private func expectEPUB(
        name: String,
        title: String,
        author: String,
        characterCount: Int,
        wordCount: Int,
        firstWord: String,
        lastWord: String
    ) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        let result = try EPUBExtractor().extractText(from: Data(contentsOf: url))
        let words = Book.tokenize(result.text)

        #expect(result.title == title)
        #expect(result.author == author)
        #expect(result.text.count == characterCount)
        #expect(words.count == wordCount)
        #expect(words.first == firstWord)
        #expect(words.last == lastWord)
    }
}
