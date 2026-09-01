enum WatchBookDetailPresentation {
    static func latestBook(for book: WatchBook, in library: WatchLibrary) -> WatchBook {
        library.books.first { $0.id == book.id } ?? book
    }

    static func progressPercentage(for book: WatchBook) -> Int {
        Int(book.progress * 100)
    }
}
