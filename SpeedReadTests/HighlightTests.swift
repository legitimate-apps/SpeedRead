import Testing
import Foundation
@testable import SpeedRead

@Suite("Highlight Model Tests")
struct HighlightTests {
    @Test func highlightInitializesCorrectly() {
        let highlight = Highlight(startWordIndex: 10, endWordIndex: 25, highlightedText: "the quick brown fox")
        #expect(highlight.startWordIndex == 10)
        #expect(highlight.endWordIndex == 25)
        #expect(highlight.highlightedText == "the quick brown fox")
        #expect(highlight.book == nil)
    }

    @Test func highlightTextCapture() {
        let words = ["Once", "upon", "a", "time", "in", "a", "land"]
        let text = Highlight.captureText(from: words, start: 1, end: 4)
        #expect(text == "upon a time in")
    }

    @Test func highlightWordCount() {
        let highlight = Highlight(startWordIndex: 10, endWordIndex: 25, highlightedText: "some text")
        #expect(highlight.wordSpan == 16)
    }
}
