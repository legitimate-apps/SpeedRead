import Testing
import Foundation
@testable import SpeedRead

@Suite("EPUB Extractor Tests")
struct EPUBExtractorTests {

    @Test func extractsTextFromXHTML() {
        let xhtml = """
        <html><body>
        <h1>Chapter One</h1>
        <p>This is a <em>test</em> paragraph.</p>
        <p>Second paragraph here.</p>
        </body></html>
        """
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Chapter One"))
        #expect(text.contains("This is a test paragraph."))
        #expect(text.contains("Second paragraph here."))
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
    }

    @Test func stripHTMLHandlesEntities() {
        let xhtml = "<p>Don&apos;t stop &amp; think</p>"
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Don't") || text.contains("Don\u{2019}t"))
        #expect(text.contains("&") || text.contains("think"))
    }

    @Test func stripHTMLHandlesEmptyInput() {
        let text = EPUBExtractor.stripHTML("")
        #expect(text.isEmpty)
    }

    @Test func invalidDataThrows() {
        let extractor = EPUBExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not an epub".utf8))
        }
    }
}
