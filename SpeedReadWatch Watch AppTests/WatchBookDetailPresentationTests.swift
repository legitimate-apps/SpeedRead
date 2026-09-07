import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch book detail presentation")
@MainActor
struct WatchBookDetailPresentationTests {
    @Test func syncedLibraryCopyReplacesTheStaleNavigationValue() {
        let stale = makeBook(index: 1)
        var synced = stale
        synced.lastReadIndex = 3
        let unrelated = makeBook(index: 2)
        let library = WatchLibrary(books: [unrelated, synced], currentBookId: synced.id)

        #expect(WatchBookDetailPresentation.latestBook(for: stale, in: library) == synced)
    }

    @Test func missingSyncedCopyFallsBackToTheNavigationValue() {
        let stale = makeBook(index: 1)

        #expect(WatchBookDetailPresentation.latestBook(
            for: stale,
            in: .empty
        ) == stale)
    }

    @Test func progressPercentagePreservesTheExistingTruncationBoundary() {
        #expect(WatchBookDetailPresentation.progressPercentage(for: makeBook(index: 0)) == 0)
        #expect(WatchBookDetailPresentation.progressPercentage(for: makeBook(index: 2)) == 50)
        #expect(WatchBookDetailPresentation.progressPercentage(for: makeBook(index: 3)) == 75)
    }

    private func makeBook(index: Int) -> WatchBook {
        WatchBook(
            id: UUID(), title: "Book", author: "Author",
            text: "zero one two three", lastReadIndex: index,
            lastReadDate: nil, wordCount: 4,
            dateAdded: Date(timeIntervalSince1970: 1)
        )
    }
}
