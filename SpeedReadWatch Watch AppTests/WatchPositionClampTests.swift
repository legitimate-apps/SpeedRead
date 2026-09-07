import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch position clamp boundaries")
struct WatchPositionClampTests {
    @Test(arguments: [-100, 1000])
    func progressAndCrownClampBothSides(index: Int) {
        // Mutation: omit either bound in watch progress, crown-to-word, or word-to-crown conversion.
        let book = makeBook(index: index)
        let expected = index < 0 ? 0 : 2
        #expect(book.progress == Double(expected) / 3)
        #expect(CrownSeek.crownValue(forWordIndex: index, wordCount: 3) == Double(2 - expected))
        #expect(CrownSeek.wordIndex(forCrownValue: Double(index), wordCount: 3) == 2 - expected)
    }

    @Test(arguments: [-100, 1000])
    func libraryWritesClampReadingBrowseAndIncomingHighWater(index: Int) {
        // Mutation: bypass either bound at any library write; a negative legacy high-water
        // prevents max(local, incoming) from masking a missing incoming lower bound.
        let book = makeBook(index: -200)
        var library = WatchLibrary(books: [book], currentBookId: book.id)
        let expected = index < 0 ? 0 : 2
        let updatedReading = library.updatePosition(bookId: book.id, index: index, furthestReadWordIndex: index)
        #expect(updatedReading)
        #expect(library.currentBook?.lastReadIndex == expected)
        #expect(library.currentBook?.browseWordIndex == expected)
        #expect(library.currentBook?.furthestReadWordIndex == expected)

        library = WatchLibrary(books: [book], currentBookId: book.id)
        let updatedBrowse = library.updateBrowsePosition(bookId: book.id, index: index)
        #expect(updatedBrowse)
        #expect(library.currentBook?.browseWordIndex == expected)
        #expect(library.currentBook?.lastReadIndex == -200)

        library = WatchLibrary(books: [book], currentBookId: book.id)
        let updatedFurthest = library.mergeFurthestReadPosition(bookId: book.id, index: index)
        #expect(updatedFurthest)
        #expect(library.currentBook?.furthestReadWordIndex == expected)
        #expect(library.currentBook?.lastReadIndex == -200)
    }

    private func makeBook(index: Int) -> WatchBook {
        WatchBook(id: UUID(), title: "Boundary", author: "", text: "zero one two",
            lastReadIndex: index, lastReadDate: nil, furthestReadWordIndex: -200,
            wordCount: 3, dateAdded: Date(timeIntervalSince1970: 100))
    }
}
