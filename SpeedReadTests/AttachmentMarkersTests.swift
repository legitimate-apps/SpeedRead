import Testing
@testable import SpeedRead

@Suite("Attachment markers")
struct AttachmentMarkersTests {
    @Test func aLineHoldingOnlyMarkersGoesEntirely() {
        #expect(AttachmentMarkers.removed(from: "\u{FFFC}\nPicture here\nThe end\n\u{FFFC}\n\u{FFFC}") == "Picture here\nThe end")
        #expect(AttachmentMarkers.removed(from: "\u{FFFC} \u{FFFC}\u{FFFC}") == "")
    }

    @Test func aMarkerBetweenWordsLeavesThemSeparate() {
        #expect(AttachmentMarkers.removed(from: "left\u{FFFC}right") == "left right")
        #expect(AttachmentMarkers.removed(from: "left \u{FFFC} right\nnext") == "left right\nnext")
    }

    @Test func noMarkerWordSurvivesTokenizing() {
        let words = Book.tokenize(AttachmentMarkers.removed(from: "\u{FFFC}\none\u{FFFC}two \u{FFFC}\n\nthree"))
        #expect(words == ["one", "two", "three"])
    }

    @Test func textWithNoMarkerComesBackExactly() {
        let text = "  two  spaces\r\n\n\ttabbed \u{2028}line\n"
        #expect(AttachmentMarkers.removed(from: text) == text)
    }

    @Test func blankLinesBesideAMarkerStayParagraphBreaks() {
        #expect(AttachmentMarkers.removed(from: "one\n\n\u{FFFC}\n\ntwo") == "one\n\n\ntwo")
    }
}
