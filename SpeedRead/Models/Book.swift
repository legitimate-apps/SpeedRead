//  Book.swift
import Foundation
import SwiftData

enum BookTokenCache {
    static func ensure(tokens: inout [String], wordCount: inout Int, extractedText: String) {
        guard tokens.isEmpty else { return }
        let migratedTokens = Book.tokenize(extractedText)
        tokens = migratedTokens
        if wordCount != migratedTokens.count {
            wordCount = migratedTokens.count
        }
    }
}

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var extractedText: String
    var sourceFileName: String
    var dateAdded: Date
    var lastReadWordIndex: Int
    var lastReadDate: Date?
    var wordCount: Int

    /// Tokens persisted at import so RSVP and reader don't re-tokenize the entire
    /// book on every access. Empty for books imported before this field existed —
    /// `words` falls back to live tokenization in that case.
    private var tokenizedWords: [String] = []

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight] = []

    init(
        title: String,
        author: String,
        extractedText: String,
        sourceFileName: String
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.extractedText = extractedText
        self.sourceFileName = sourceFileName
        self.dateAdded = Date()
        self.lastReadWordIndex = 0
        self.lastReadDate = nil
        let tokens = Book.tokenize(extractedText)
        self.tokenizedWords = tokens
        self.wordCount = tokens.count
    }

    /// Splits text into RSVP-friendly tokens, breaking hyphenated words
    /// into separate display tokens while preserving em-dashes and en-dashes.
    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .flatMap(splitHyphens)
    }

    /// Splits a word on ASCII hyphens, keeping the hyphen attached to the left part.
    /// Only splits when both sides of a hyphen contain at least one letter, so pure
    /// hyphen runs ("--"), leading hyphens ("-prefix"), and em/en-dashes are preserved.
    private static func splitHyphens(_ word: Substring) -> [String] {
        var tokens: [String] = []
        var segmentStart = word.startIndex
        var i = word.startIndex
        while i < word.endIndex {
            if word[i] == "-",
               word[segmentStart..<i].contains(where: \.isLetter),
               word[word.index(after: i)...].contains(where: \.isLetter) {
                let next = word.index(after: i)
                tokens.append(String(word[segmentStart..<next]))
                segmentStart = next
            }
            i = word.index(after: i)
        }
        if segmentStart < word.endIndex {
            tokens.append(String(word[segmentStart..<word.endIndex]))
        }
        return tokens
    }

    var words: [String] {
        if !tokenizedWords.isEmpty {
            return tokenizedWords
        }
        return Book.tokenize(extractedText)
    }

    /// One-shot migration helper for books imported before `tokenizedWords` existed.
    /// Idempotent and safe to call from any view's `.task`.
    func ensureTokensCached() {
        BookTokenCache.ensure(
            tokens: &tokenizedWords,
            wordCount: &wordCount,
            extractedText: extractedText
        )
    }

    var progress: Double {
        guard wordCount > 0 else { return 0.0 }
        return Double(lastReadWordIndex) / Double(wordCount)
    }
}
