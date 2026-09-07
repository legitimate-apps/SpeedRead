import Testing
import Foundation
@testable import SpeedRead

@Suite("Reader Paragraphizer")
@MainActor
struct ReaderParagraphTests {

    @Test func splitsBlockOnDoubleNewlines() {
        let text = "First paragraph here.\n\nSecond paragraph here.\n\nThird block."
        let words = Book.tokenize(text)
        let paragraphs = ReaderParagraphizer.paragraphs(from: text, allWords: words)

        #expect(paragraphs.count == 3)
        #expect(paragraphs[0].words == ["First", "paragraph", "here."])
        #expect(paragraphs[1].startIndex == 3)
        #expect(paragraphs[2].startIndex == 6)
    }

    @Test func preservesAbsoluteIndices() {
        let text = "alpha beta\n\ngamma delta epsilon\n\nzeta"
        let words = Book.tokenize(text)
        let paragraphs = ReaderParagraphizer.paragraphs(from: text, allWords: words)

        // Reconstruct flat by walking paragraphs.
        var flat: [String] = []
        for p in paragraphs {
            for (i, w) in p.words.enumerated() {
                let absolute = p.startIndex + i
                #expect(words[absolute] == w)
                flat.append(w)
            }
        }
        #expect(flat == words)
    }

    @Test func emptyTextProducesNoParagraphs() {
        let paragraphs = ReaderParagraphizer.paragraphs(from: "", allWords: [])
        #expect(paragraphs.isEmpty)
    }

    @Test func singleBlockBecomesOneParagraph() {
        let text = "All on one line with no breaks at all."
        let words = Book.tokenize(text)
        let paragraphs = ReaderParagraphizer.paragraphs(from: text, allWords: words)
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].startIndex == 0)
        #expect(paragraphs[0].words == words)
    }

    @Test func handlesCRLFLineEndings() {
        let text = "Para one.\r\n\r\nPara two."
        let words = Book.tokenize(text)
        let paragraphs = ReaderParagraphizer.paragraphs(from: text, allWords: words)
        #expect(paragraphs.count == 2)
    }
}
