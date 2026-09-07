import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch library presentation")
@MainActor
struct WatchLibraryPresentationTests {
    @Test func nowReadingProgressIsHiddenAtZeroAndTruncatedAboveZero() {
        #expect(WatchLibraryPresentation.progressText(for: makeBook(index: 0)) == nil)
        #expect(WatchLibraryPresentation.progressText(for: makeBook(index: 1)) == "33% complete")
    }

    @Test func currentMarkerTakesPrecedenceOverProgressRing() {
        let book = makeBook(index: 1)

        #expect(WatchLibraryPresentation.accessory(
            for: book,
            currentBookID: book.id
        ) == .current)
        #expect(WatchLibraryPresentation.accessory(
            for: book,
            currentBookID: UUID()
        ) == .progress(1.0 / 3.0))
        #expect(WatchLibraryPresentation.accessory(
            for: makeBook(index: 0),
            currentBookID: nil
        ) == .none)
    }

    @Test func allBooksHeaderExistsOnlyAlongsideNowReading() {
        #expect(WatchLibraryPresentation.showsAllBooksHeader(currentBook: makeBook(index: 0)))
        #expect(!WatchLibraryPresentation.showsAllBooksHeader(currentBook: nil))
    }

    private func makeBook(index: Int) -> WatchBook {
        WatchBook(
            id: UUID(), title: "Book", author: "Author",
            text: "zero one two", lastReadIndex: index,
            lastReadDate: nil, wordCount: 3,
            dateAdded: Date(timeIntervalSince1970: 1)
        )
    }
}
