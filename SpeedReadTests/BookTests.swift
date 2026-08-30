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
        #expect(book.browseWordIndex == 0)
        #expect(book.furthestReadWordIndex == 0)
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

    // MARK: - Tokenization Tests

    @Test func tokenizeSplitsHyphenatedWords() {
        let tokens = Book.tokenize("self-awareness is key")
        #expect(tokens == ["self-", "awareness", "is", "key"])
    }

    @Test func tokenizePreservesEmDash() {
        let tokens = Book.tokenize("hello\u{2014}world")
        #expect(tokens == ["hello\u{2014}world"])
    }

    @Test func tokenizePreservesEnDash() {
        let tokens = Book.tokenize("pages 10\u{2013}20")
        #expect(tokens == ["pages", "10\u{2013}20"])
    }

    @Test func tokenizeHandlesMultipleHyphens() {
        let tokens = Book.tokenize("state-of-the-art design")
        #expect(tokens == ["state-", "of-", "the-", "art", "design"])
    }

    @Test func tokenizeDoesNotSplitPureHyphens() {
        let tokens = Book.tokenize("hello -- world")
        #expect(tokens == ["hello", "--", "world"])
    }

    @Test func tokenizeDoesNotSplitLeadingHyphen() {
        let tokens = Book.tokenize("-prefix word")
        #expect(tokens == ["-prefix", "word"])
    }

    @Test func wordCountMatchesTokenizedWords() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "self-awareness is well-known",
            sourceFileName: "t.epub"
        )
        #expect(book.wordCount == 5)
        #expect(book.words.count == 5)
    }

    @Test func ensureTokensCachedIsIdempotentForAnAlreadyMigratedBook() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "persisted token coordinates",
            sourceFileName: "t.txt"
        )
        let originalWords = book.words
        let originalCount = book.wordCount
        book.extractedText = "different source text must not replace persisted coordinates"

        book.ensureTokensCached()
        book.ensureTokensCached()

        #expect(book.words == originalWords)
        #expect(book.wordCount == originalCount)
    }

    @Test func legacyTokenCacheMigrationUsesTheCanonicalTokenizer() {
        var legacyTokens: [String] = []
        var staleWordCount = 99
        let text = "self-awareness stays aligned"

        BookTokenCache.ensure(
            tokens: &legacyTokens,
            wordCount: &staleWordCount,
            extractedText: text
        )

        #expect(legacyTokens == Book.tokenize(text))
        #expect(legacyTokens == ["self-", "awareness", "stays", "aligned"])
        #expect(staleWordCount == 4)
    }

    @Test func tokenCacheHelperDoesNotRecomputePersistedTokens() {
        var persistedTokens = ["persisted", "coordinate"]
        var persistedWordCount = 2

        BookTokenCache.ensure(
            tokens: &persistedTokens,
            wordCount: &persistedWordCount,
            extractedText: "replacement text"
        )

        #expect(persistedTokens == ["persisted", "coordinate"])
        #expect(persistedWordCount == 2)
    }

    @Test func legacyPositionMarkersMigrateFromTheExistingReadingPosition() {
        var browseWordIndex = -1
        var furthestReadWordIndex = -1

        BookPositionMigration.ensure(
            browseWordIndex: &browseWordIndex,
            furthestReadWordIndex: &furthestReadWordIndex,
            lastReadWordIndex: 37
        )

        #expect(browseWordIndex == 37)
        #expect(furthestReadWordIndex == 37)
    }

    @Test func positionMarkerMigrationNeverOverwritesPersistedMarkers() {
        var browseWordIndex = 12
        var furthestReadWordIndex = 44

        BookPositionMigration.ensure(
            browseWordIndex: &browseWordIndex,
            furthestReadWordIndex: &furthestReadWordIndex,
            lastReadWordIndex: 20
        )

        #expect(browseWordIndex == 12)
        #expect(furthestReadWordIndex == 44)
    }
}
