import Testing
import Foundation
@testable import SpeedRead

@Suite("Bookmark Model Tests")
struct BookmarkTests {
    @Test func bookmarkInitializesCorrectly() {
        let bookmark = Bookmark(wordIndex: 42, previewText: "the quick brown fox jumped")
        #expect(bookmark.wordIndex == 42)
        #expect(bookmark.previewText == "the quick brown fox jumped")
        #expect(bookmark.book == nil)
    }

    @Test func bookmarkPreviewTextGeneration() {
        let words = ["Once", "upon", "a", "time", "in", "a", "land", "far", "away", "there"]
        let preview = Bookmark.previewText(from: words, at: 4, windowSize: 5)
        // at index 4, half=2, start=max(0,4-2)=2, end=min(10,2+5)=7 → "a time in a land"
        #expect(preview == "a time in a land")
    }

    @Test func bookmarkPreviewAtStart() {
        let words = ["Once", "upon", "a", "time", "in"]
        let preview = Bookmark.previewText(from: words, at: 0, windowSize: 5)
        #expect(preview == "Once upon a time in")
    }

    @Test func bookmarkPreviewAtEnd() {
        let words = ["Once", "upon", "a", "time", "in"]
        let preview = Bookmark.previewText(from: words, at: 4, windowSize: 5)
        // at index 4, half=2, start=max(0,4-2)=2, end=min(5,2+5)=5 → "a time in"
        #expect(preview == "a time in")
    }
}
