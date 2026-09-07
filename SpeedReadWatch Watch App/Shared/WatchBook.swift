//  WatchBook.swift
import Foundation

struct WatchBook: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let text: String
    var lastReadIndex: Int
    var lastReadDate: Date?
    // Local playback completion only; never inferred from a phone position payload.
    var hasFinishedLocally: Bool = false
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
        chapters: [ChapterMark] = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, text, lastReadIndex, lastReadDate, hasFinishedLocally
        case browseWordIndex, furthestReadWordIndex, wordCount, dateAdded, chapters
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        text = try container.decode(String.self, forKey: .text)
        lastReadIndex = try container.decode(Int.self, forKey: .lastReadIndex)
        lastReadDate = try container.decodeIfPresent(Date.self, forKey: .lastReadDate)
        hasFinishedLocally = try container.decodeIfPresent(Bool.self, forKey: .hasFinishedLocally) ?? false
        browseWordIndex = try container.decodeIfPresent(Int.self, forKey: .browseWordIndex)
            ?? lastReadIndex
        furthestReadWordIndex = try container.decodeIfPresent(Int.self, forKey: .furthestReadWordIndex)
            ?? lastReadIndex
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        chapters = try container.decodeIfPresent([ChapterMark].self, forKey: .chapters) ?? []
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
        furthestReadWordIndex: Int? = nil
    ) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return false }
        let upperBound = max(0, books[i].wordCount - 1)
        let clamped = ReadingPositionCoordinator.clampedIndex(index, wordCount: books[i].wordCount)
        let incomingFurthest = ReadingPositionCoordinator.clampedIndex(furthestReadWordIndex ?? clamped, wordCount: books[i].wordCount)
        if clamped < upperBound { books[i].hasFinishedLocally = false }
        books[i].lastReadIndex = clamped
        books[i].lastReadDate = timestamp
        books[i].browseWordIndex = clamped
        books[i].furthestReadWordIndex = max(books[i].furthestReadWordIndex, incomingFurthest)
        return true
    }

    @discardableResult
    mutating func markFinishedLocally(bookId: UUID) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }),
              books[i].wordCount > 0,
              books[i].lastReadIndex == books[i].wordCount - 1,
              !books[i].hasFinishedLocally else { return false }
        books[i].hasFinishedLocally = true
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
