import Testing
import Foundation
@testable import SpeedRead

@Suite("Book Model Tests")
struct BookTests {
    @Test func bookInitializesWithDefaults() {
        let book = Book(
            title: "Test Book",
            author: "Test Author",
            extractedText: "Hello world this is a test.",
            sourceFileName: "test.epub"
        )
        #expect(book.title == "Test Book")
        #expect(book.author == "Test Author")
        #expect(book.lastReadWordIndex == 0)
        #expect(book.sourceFileName == "test.epub")
        #expect(book.wordCount == 6)
    }

    @Test func wordsPropertySplitsText() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "Hello world this is a test",
            sourceFileName: "t.epub"
        )
        let words = book.words
        #expect(words.count == 6)
        #expect(book.wordCount == 6)
        #expect(words[0] == "Hello")
        #expect(words[5] == "test")
    }

    @Test func wordsHandlesMultipleSpaces() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "Hello   world\n\ntest",
            sourceFileName: "t.epub"
        )
        let words = book.words
        #expect(words.count == 3)
        #expect(book.wordCount == 3)
        #expect(words[0] == "Hello")
        #expect(words[1] == "world")
        #expect(words[2] == "test")
    }

    @Test func wordsHandlesEmptyText() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "",
            sourceFileName: "t.epub"
        )
        #expect(book.words.isEmpty)
        #expect(book.wordCount == 0)
    }

    @Test func progressCalculation() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "one two three four five six seven eight nine ten",
            sourceFileName: "t.epub"
        )
        book.lastReadWordIndex = 5
        #expect(book.progress == 0.5)
    }

    @Test func progressIsZeroWhenNoWords() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "",
            sourceFileName: "t.epub"
        )
        #expect(book.progress == 0.0)
    }
}
