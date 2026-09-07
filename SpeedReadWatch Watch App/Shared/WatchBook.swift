//  WatchBook.swift
import Foundation

struct WatchBook: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let text: String
    var lastReadIndex: Int
    var lastReadDate: Date?
    var finishedAt: Date?
    // Keep the existing presentation name; completion may now arrive from either device.
    var hasFinishedLocally: Bool { finishedAt != nil }
    var browseWordIndex: Int
    var furthestReadWordIndex: Int
    let wordCount: Int
    let dateAdded: Date
    let chapters: [ChapterMark]

    init(
        id: UUID,
        title: String,
        author: String,
        text: String,
        lastReadIndex: Int,
        lastReadDate: Date?,
        browseWordIndex: Int? = nil,
        furthestReadWordIndex: Int? = nil,
        wordCount: Int,
        dateAdded: Date,
        chapters: [ChapterMark] = [],
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.text = text
        self.lastReadIndex = lastReadIndex
        self.lastReadDate = lastReadDate
        self.browseWordIndex = browseWordIndex ?? lastReadIndex
        self.furthestReadWordIndex = furthestReadWordIndex ?? lastReadIndex
        self.wordCount = wordCount
        self.dateAdded = dateAdded
        self.chapters = chapters
        self.finishedAt = finishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, text, lastReadIndex, lastReadDate, hasFinishedLocally
        case browseWordIndex, furthestReadWordIndex, wordCount, dateAdded, chapters, finishedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        text = try container.decode(String.self, forKey: .text)
        lastReadIndex = try container.decode(Int.self, forKey: .lastReadIndex)
        lastReadDate = try container.decodeIfPresent(Date.self, forKey: .lastReadDate)
        browseWordIndex = try container.decodeIfPresent(Int.self, forKey: .browseWordIndex)
            ?? lastReadIndex
        furthestReadWordIndex = try container.decodeIfPresent(Int.self, forKey: .furthestReadWordIndex)
            ?? lastReadIndex
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        chapters = try container.decodeIfPresent([ChapterMark].self, forKey: .chapters) ?? []
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        if finishedAt == nil,
           try container.decodeIfPresent(Bool.self, forKey: .hasFinishedLocally) == true {
            // Legacy watch stores have no original completion date; preserve their marker
            // using the last commit timestamp (or import date if that too is absent).
            finishedAt = lastReadDate ?? dateAdded
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(text, forKey: .text)
        try container.encode(lastReadIndex, forKey: .lastReadIndex)
        try container.encodeIfPresent(lastReadDate, forKey: .lastReadDate)
        try container.encode(hasFinishedLocally, forKey: .hasFinishedLocally)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encode(browseWordIndex, forKey: .browseWordIndex)
        try container.encode(furthestReadWordIndex, forKey: .furthestReadWordIndex)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(chapters, forKey: .chapters)
    }

    var words: [String] {
        BookTokenizer.tokenize(text)
    }

    var progress: Double {
        guard wordCount > 0 else { return 0 }
        if hasFinishedLocally { return 1 }
        return Double(ReadingPositionCoordinator.clampedIndex(lastReadIndex, wordCount: wordCount)) / Double(wordCount)
    }
}

struct WatchLibrary: Codable, Equatable {
    var books: [WatchBook]
    var currentBookId: UUID?

    static let empty = WatchLibrary(books: [], currentBookId: nil)

    var currentBook: WatchBook? {
        guard let id = currentBookId else { return nil }
        return books.first { $0.id == id }
    }

    var sortedBooks: [WatchBook] {
        books.sorted { $0.dateAdded > $1.dateAdded }
    }

    mutating func addBook(_ book: WatchBook) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.append(book)
        currentBookId = book.id
    }

    mutating func removeBook(id: UUID) {
        books.removeAll { $0.id == id }
        if currentBookId == id {
            currentBookId = sortedBooks.first?.id
        }
    }

    @discardableResult
    mutating func updatePosition(
        bookId: UUID,
        index: Int,
        timestamp: Date = Date(),
        furthestReadWordIndex: Int? = nil,
        didFinish: Bool = false,
        finishedAt: Date? = nil
    ) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return false }
        let clamped = ReadingPositionCoordinator.clampedIndex(index, wordCount: books[i].wordCount)
        let incomingFurthest = ReadingPositionCoordinator.clampedIndex(furthestReadWordIndex ?? clamped, wordCount: books[i].wordCount)
        books[i].finishedAt = ReadingPositionCoordinator.completionDate(
            didFinish: didFinish, index: clamped, wordCount: books[i].wordCount,
            existingDate: books[i].finishedAt, incomingDate: finishedAt, now: timestamp
        )
        books[i].lastReadIndex = clamped
        books[i].lastReadDate = timestamp
        books[i].browseWordIndex = clamped
        books[i].furthestReadWordIndex = max(books[i].furthestReadWordIndex, incomingFurthest)
        return true
    }

    @discardableResult
    mutating func updateBrowsePosition(bookId: UUID, index: Int) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return false }
        books[i].browseWordIndex = ReadingPositionCoordinator.clampedIndex(index, wordCount: books[i].wordCount)
        return true
    }

    @discardableResult
    mutating func mergeFurthestReadPosition(bookId: UUID, index: Int) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return false }
        let clamped = ReadingPositionCoordinator.clampedIndex(index, wordCount: books[i].wordCount)
        guard clamped > books[i].furthestReadWordIndex else { return false }
        books[i].furthestReadWordIndex = clamped
        return true
    }

    mutating func setCurrentBook(id: UUID) {
        guard books.contains(where: { $0.id == id }) else { return }
        currentBookId = id
    }
}

struct WatchLibraryStore {
    let fileURL: URL

    func load() -> WatchLibrary {
        guard let data = try? Data(contentsOf: fileURL),
              let library = try? JSONDecoder().decode(WatchLibrary.self, from: data) else {
            return .empty
        }
        return library
    }

    func save(_ library: WatchLibrary) throws {
        let data = try JSONEncoder().encode(library)
        try data.write(to: fileURL, options: .atomic)
    }
}
