//  Book.swift
import Foundation
import SwiftData

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
        self.wordCount = Book.tokenize(extractedText).count
    }

    /// Splits text into RSVP-friendly tokens, breaking hyphenated words
    /// into separate display tokens while preserving em-dashes and en-dashes.
    static func tokenize(_ text: String) -> [String] {
        let rawWords = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var tokens: [String] = []
        for word in rawWords {
            let parts = splitHyphens(word)
            tokens.append(contentsOf: parts)
        }
        return tokens
    }

    /// Splits a single word on ASCII hyphens, keeping the hyphen on the left part.
    /// Only splits when both sides of the hyphen contain at least one letter.
    /// Does not split on em-dashes (\u{2014}) or en-dashes (\u{2013}).
    private static func splitHyphens(_ word: String) -> [String] {
        let hyphen: Character = "-"
        var results: [String] = []
        var current = ""

        let chars = Array(word)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == hyphen {
                // Check that the left side (current) has a letter and the right side has a letter
                let leftHasLetter = current.unicodeScalars.contains { CharacterSet.letters.contains($0) }
                let rightHasLetter = chars[(i + 1)...].contains { c in
                    c.unicodeScalars.contains { CharacterSet.letters.contains($0) }
                }
                if leftHasLetter && rightHasLetter {
                    current.append(hyphen)
                    results.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            } else {
                current.append(ch)
            }
            i += 1
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    var words: [String] {
        Book.tokenize(extractedText)
    }

    var progress: Double {
        guard wordCount > 0 else { return 0.0 }
        return Double(lastReadWordIndex) / Double(wordCount)
    }
}
