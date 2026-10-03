import CryptoKit
import Foundation
import Testing
@testable import SpeedRead

@Suite("Chapter token-stream identity")
@MainActor
struct ChapterTokenIdentityTests {
    /// A changed fingerprint moves every position stored against a fresh import, so it changes only
    /// on purpose. The EPUB values last changed on 2026-10-03, when head titles and style sheets
    /// stopped being read as text (13, 46 and 34 words, counted independently in
    /// BundledSampleBookTests). Books already imported keep their stored text and are unaffected.
    @Test func bundledBooksRetainTheirExactExtractedTextAndTokenStreams() throws {
        let expected: [String: (text: String, tokens: String)] = [
            "TheYellowWallpaper.epub": (
                "65afb4a56676ffa59aa60efa5a28e90591594713792a524bd9ac1590c4cdc59a",
                "6a6f17561d3008304b4e08b1f8069ee39539af7dc547ee9837324e50370d92eb"
            ),
            "TheMetamorphosis.epub": (
                "5d45d886570cdddd72195146d8d701ebbe52396e80286b32f5d628284351de92",
                "603ae6c1a2812f2fab99269400fe6f38d0be9e5829a443a8b99faf99caee0835"
            ),
            "AChristmasCarol.epub": (
                "0dc3693dd41795fc70c3d0e3ca3af821be2f94328db6a9e30078a201812ed368",
                "c0a00492930ff83b79acfd21b9acb3cae2e0c711d30e37a8ba62c9abfe512f54"
            ),
            "AChristmasCarol.pdf": (
                "6933321011b85584696482fa42f33b064bc6292f9e7b48622b34cf6a3ad38136",
                "367cec9836d8076935e1d3bfb1b180474b8a52c47ebb7e3313df41bf95a21578"
            )
        ]

        for filename in expected.keys.sorted() {
            let parts = filename.split(separator: ".", maxSplits: 1).map(String.init)
            let url = try #require(Bundle.main.url(
                forResource: parts[0],
                withExtension: parts[1]
            ))
            let data = try Data(contentsOf: url)
            let result = try parts[1] == "epub"
                ? EPUBExtractor().extractText(from: data)
                : PDFExtractor().extractText(from: data)
            let expectedFingerprint = try #require(expected[filename])

            #expect(fingerprint(Data(result.text.utf8)) == expectedFingerprint.text)
            #expect(tokenFingerprint(Book.tokenize(result.text)) == expectedFingerprint.tokens)
        }
    }

    @Test func bundledEPUBsExposeRealNavigationTitlesAtValidTokenOffsets() throws {
        let expectedTitleFragments = [
            "TheYellowWallpaper.epub": "YELLOW WALLPAPER",
            "TheMetamorphosis.epub": "METAMORPHOSIS",
            "AChristmasCarol.epub": "STAVE ONE"
        ]

        for filename in expectedTitleFragments.keys.sorted() {
            let data = try Data(contentsOf: try #require(
                Bundle.main.url(forResource: filename, withExtension: nil)
            ))
            let result = try EPUBExtractor().extractText(from: data)
            let words = Book.tokenize(result.text)
            let titleFragment = try #require(expectedTitleFragments[filename])

            #expect(!result.chapters.isEmpty)
            #expect(result.chapters.contains {
                $0.title.uppercased().contains(titleFragment)
            })
            #expect(result.chapters.allSatisfy {
                words.indices.contains($0.startWordIndex)
            })
            #expect(result.chapters.map(\.startWordIndex) ==
                result.chapters.map(\.startWordIndex).sorted())
        }
    }

    @Test func bundledEPUBChapterOffsetsUsePostHyphenCanonicalTokens() throws {
        let data = try Data(contentsOf: try #require(
            Bundle.main.url(forResource: "AChristmasCarol.epub", withExtension: nil)
        ))
        let result = try EPUBExtractor().extractText(from: data)
        let book = Book(
            title: "A Christmas Carol",
            author: "Charles Dickens",
            extractedText: result.text,
            sourceFileName: "AChristmasCarol.epub",
            chapters: result.chapters
        )
        let mark = try #require(result.chapters.first {
            $0.title.uppercased().contains("STAVE FIVE")
        })
        let firstChapterToken = try #require(Book.tokenize(mark.title).first)

        // This fixture contains letter-letter ASCII hyphens before STAVE FIVE,
        // so canonical token count must exceed whitespace-only word count.
        #expect(
            Book.tokenize(result.text).count
                > result.text.split(whereSeparator: \.isWhitespace).count
        )
        #expect(book.words[mark.startWordIndex] == firstChapterToken)
    }

    private func tokenFingerprint(_ tokens: [String]) -> String {
        var data = Data()
        for token in tokens {
            var length = UInt64(token.utf8.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(contentsOf: token.utf8)
        }
        return fingerprint(data)
    }

    private func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
