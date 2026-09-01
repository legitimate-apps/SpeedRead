import Foundation

enum WatchLibraryPresentation {
    enum Accessory: Equatable {
        case current
        case progress(Double)
        case none
    }

    static func progressText(for book: WatchBook) -> String? {
        guard book.progress > 0 else { return nil }
        return "\(Int(book.progress * 100))% complete"
    }

    static func accessory(for book: WatchBook, currentBookID: UUID?) -> Accessory {
        if book.id == currentBookID {
            return .current
        }
        if book.progress > 0 {
            return .progress(book.progress)
        }
        return .none
    }

    static func showsAllBooksHeader(currentBook: WatchBook?) -> Bool {
        currentBook != nil
    }
}
