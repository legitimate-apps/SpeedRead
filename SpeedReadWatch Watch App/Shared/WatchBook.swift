//  WatchBook.swift
import Foundation

struct WatchBook: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let text: String
    var lastReadIndex: Int
    var lastReadDate: Date?
    let wordCount: Int
    let dateAdded: Date

    var words: [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var progress: Double {
        guard wordCount > 0 else { return 0 }
        return Double(lastReadIndex) / Double(wordCount)
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
    mutating func updatePosition(bookId: UUID, index: Int, timestamp: Date = Date()) -> Bool {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return false }
        books[i].lastReadIndex = min(max(0, index), max(0, books[i].wordCount - 1))
        books[i].lastReadDate = timestamp
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
