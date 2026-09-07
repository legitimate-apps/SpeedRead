import SwiftData
import Testing
@testable import SpeedRead

@Suite("RSVP annotation actions")
@MainActor
struct RSVPAnnotationActionTests {
    @Test func bookmarkInsertsClampedDraftWithTheSelectedBookRelationship() throws {
        // Mutations: omit bookmark.book, use the raw index, or copy the wrong preview text.
        let container = try makeContainer()
        let book = makeBook()
        container.mainContext.insert(book)
        let session = RSVPPresentationSession()
        session.load(book: book, engine: RSVPEngine(), wpm: 300)
        session.addBookmark(at: 99, book: book, modelContext: container.mainContext)
        let bookmarks = try container.mainContext.fetch(FetchDescriptor<Bookmark>())
        let bookmark = try #require(bookmarks.first)
        #expect(bookmarks.count == 1)
        #expect(bookmark.wordIndex == 4)
        #expect(bookmark.previewText == "two three four")
        #expect(bookmark.book?.id == book.id)
    }

    @Test func firstHighlightTapOnlyStartsSelectionAndSecondInsertsOrderedRange() throws {
        // Mutations: insert on the first tap, omit the book relationship,
        // swap endpoints, or return false after insertion (suppressing view feedback).
        let container = try makeContainer()
        let book = makeBook()
        container.mainContext.insert(book)
        let session = RSVPPresentationSession()
        session.load(book: book, engine: RSVPEngine(), wpm: 300)
        #expect(!session.toggleHighlight(at: 3, book: book, modelContext: container.mainContext))
        #expect(session.highlightStartIndex == 3)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Highlight>()) == 0)
        #expect(session.toggleHighlight(at: 1, book: book, modelContext: container.mainContext))
        let highlights = try container.mainContext.fetch(FetchDescriptor<Highlight>())
        let highlight = try #require(highlights.first)
        #expect(highlights.count == 1)
        #expect(highlight.startWordIndex == 1)
        #expect(highlight.endWordIndex == 3)
        #expect(highlight.highlightedText == "one two three")
        #expect(highlight.book?.id == book.id)
        #expect(session.highlightStartIndex == nil)
    }

    @Test func emptyHighlightDoesNotInsertOrRequestCompletionFeedback() throws {
        // Mutation: treat the empty-stream nil draft as a completed selection.
        let container = try makeContainer()
        let book = Book(title: "Empty", author: "Test", extractedText: "", sourceFileName: "empty.txt")
        let session = RSVPPresentationSession()
        session.load(book: book, engine: RSVPEngine(), wpm: 300)
        #expect(!session.toggleHighlight(at: 0, book: book, modelContext: container.mainContext))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Highlight>()) == 0)
        #expect(session.highlightStartIndex == nil)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeBook() -> Book {
        Book(title: "Test", author: "Test", extractedText: "zero one two three four", sourceFileName: "test.txt")
    }
}
