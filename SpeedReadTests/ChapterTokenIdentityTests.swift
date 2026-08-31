import CryptoKit
import Foundation
import Testing
@testable import SpeedRead

@Suite("Chapter token-stream identity")
struct ChapterTokenIdentityTests {
    @Test func bundledBooksRetainTheirExactExtractedTextAndTokenStreams() throws {
        let expected: [String: (text: String, tokens: String)] = [
            "TheYellowWallpaper.epub": (
                "e4cef268cec644eebf88f0d6861e9b52ddc474763143abef0b58ff26d0265129",
                "f3089ba3defc469d11587bc3312f9fc06cba9afe0af432df13906a183330c6f8"
            ),
            "TheMetamorphosis.epub": (
                "b153e5f9e423890eb8c51bf62c4e23bffd1705bbb625b8cf59723fcce095953d",
                "e83b7c7f7b325da85c766a10bfd7142304887ad61af3eb192528006002aa3ae2"
            ),
            "AChristmasCarol.epub": (
                "f8bb6b62b8fd4ba2fb68dc33fdf19cdacde0a9804187c4a2366ca3552cd89a3c",
                "113d29f547428cc04fbdf07d6a10bee417d06602e7ed8d477761773bfac16423"
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
