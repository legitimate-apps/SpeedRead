import Testing
import Foundation
@testable import SpeedRead

@Suite("Highlight Model Tests")
@MainActor
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

    @Test func aNoteIsTrimmedAndABlankNoteIsNoNote() {
        let highlight = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "a b")
        let later = highlight.createdAt.addingTimeInterval(5)
        highlight.setNote("  thought \n", at: later)
        #expect(highlight.note == "thought")
        #expect(highlight.modifiedAt == later)
        highlight.setNote("   ", at: later.addingTimeInterval(1))
        #expect(highlight.note == nil)
    }

    @Test func settingTheSameNoteIsNotAChange() {
        let highlight = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "a b")
        highlight.setNote("same")
        let stamp = highlight.modifiedAt
        highlight.setNote(" same ")
        #expect(highlight.modifiedAt == stamp)
    }

    @Test func onlyThisAppsUnsentHighlightsNeedPushing() {
        let highlight = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "a b")
        #expect(highlight.needsPush)
        #expect(highlight.annotationID == highlight.id.uuidString)
        highlight.syncedAt = highlight.createdAt.addingTimeInterval(1)
        #expect(!highlight.needsPush)
        highlight.setNote("new", at: highlight.createdAt.addingTimeInterval(2))
        #expect(highlight.needsPush)

        let theirs = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "a b")
        theirs.syncID = "kr-1"
        theirs.syncSource = "koreader"
        #expect(theirs.annotationID == "kr-1")
        #expect(!theirs.isEditableOnServer)
        #expect(!theirs.needsPush)
        theirs.syncSource = "textquote"
        #expect(theirs.isEditableOnServer)
    }
}
