//  Book.swift
import Foundation
#if !os(watchOS)
import SwiftData
#endif

nonisolated enum BookTokenizer {
    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .flatMap(splitHyphens)
    }

    /// Splits a word on ASCII hyphens, keeping the hyphen attached to the left part.
    /// Only splits when both sides of a hyphen contain at least one letter, so pure
    /// hyphen runs ("--"), leading hyphens ("-prefix"), and em/en-dashes are preserved.
    static func splitHyphens(_ word: Substring) -> [String] {
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
}

#if !os(watchOS)

nonisolated enum BookTokenCache {
    static func ensure(tokens: inout [String], wordCount: inout Int, extractedText: String) {
        guard tokens.isEmpty else { return }
        let migratedTokens = Book.tokenize(extractedText)
        tokens = migratedTokens
        if wordCount != migratedTokens.count {
            wordCount = migratedTokens.count
        }
    }
}

nonisolated enum BookPositionMigration {
    static func ensure(
        browseWordIndex: inout Int,
        furthestReadWordIndex: inout Int,
        lastReadWordIndex: Int
    ) {
        if browseWordIndex < 0 {
            browseWordIndex = max(0, lastReadWordIndex)
        }
        if furthestReadWordIndex < 0 {
            furthestReadWordIndex = max(0, lastReadWordIndex)
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
    /// Completion of the current read, independent of the last visible word.
    /// Optional so existing libraries migrate with no inferred completion.
    var finishedAt: Date? = nil
    /// The place: the word on screen and highlighted in the reader, moved by any interaction and
    /// shared live with the watch. A negative value is the migration sentinel for stores created
    /// before the three-marker position model.
    var browseWordIndex: Int = -1
    /// When the place last moved, on either device. Nil until it first moves.
    var browseDate: Date? = nil

    /// Synced high-water reading mark. A negative value is the migration sentinel.
    var furthestReadWordIndex: Int = -1
    var wordCount: Int

    /// KOReader partial MD5 of the bytes this book was imported from — the key sync servers
    /// match reading progress on. Nil for books imported before it was recorded.
    var sourceDigest: String? = nil
    private var originServerID: UUID? = nil
    private var originEntryID: String? = nil
    private var originServerBookID: String? = nil

    /// Tokens persisted at import so RSVP and reader don't re-tokenize the entire
    /// book on every access. Empty for books imported before this field existed —
    /// `words` falls back to live tokenization in that case.
    private var tokenizedWords: [String] = []

    /// Real structural boundaries supplied by the source format. Empty for
    /// legacy books and formats that do not carry chapter structure.
    var chapters: [ChapterMark] = []

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight] = []

    init(
        title: String,
        author: String,
        extractedText: String,
        sourceFileName: String,
        chapters: [ChapterMark] = []
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.extractedText = extractedText
        self.sourceFileName = sourceFileName
        self.chapters = chapters
        self.dateAdded = Date()
        self.lastReadWordIndex = 0
        self.lastReadDate = nil
        self.browseWordIndex = 0
        self.furthestReadWordIndex = 0
        let tokens = Book.tokenize(extractedText)
        self.tokenizedWords = tokens
        self.wordCount = tokens.count
    }

    var origin: BookOrigin? {
        get {
            guard let originServerID, let originEntryID else { return nil }
            return BookOrigin(serverID: originServerID, entryID: originEntryID,
                              serverBookID: originServerBookID)
        }
        set {
            originServerID = newValue?.serverID
            originEntryID = newValue?.entryID
            originServerBookID = newValue?.serverBookID
        }
    }

    /// Splits text into RSVP-friendly tokens, breaking hyphenated words
    /// into separate display tokens while preserving em-dashes and en-dashes.
    static func tokenize(_ text: String) -> [String] {
        BookTokenizer.tokenize(text)
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

    func ensurePositionMarkersInitialized() {
        BookPositionMigration.ensure(
            browseWordIndex: &browseWordIndex,
            furthestReadWordIndex: &furthestReadWordIndex,
            lastReadWordIndex: lastReadWordIndex
        )
    }

    var progress: Double {
        guard wordCount > 0 else { return 0.0 }
        if finishedAt != nil { return 1.0 }
        return Double(lastReadWordIndex) / Double(wordCount)
    }

    /// Everything this phone knows about its place in the book, for the watch.
    func positionPayload() -> WatchSyncLogic.PositionPayload {
        WatchSyncLogic.PositionPayload(
            bookId: id,
            bookTitle: title,
            wordIndex: ReadingPositionCoordinator.clampedIndex(lastReadWordIndex, wordCount: wordCount),
            timestamp: lastReadDate ?? .distantPast,
            furthestReadWordIndex: max(0, furthestReadWordIndex),
            didFinish: finishedAt != nil,
            finishedAt: finishedAt,
            browseWordIndex: ReadingPositionCoordinator.clampedIndex(browseWordIndex, wordCount: wordCount),
            browseTimestamp: browseDate ?? lastReadDate ?? .distantPast
        )
    }
}
#endif
