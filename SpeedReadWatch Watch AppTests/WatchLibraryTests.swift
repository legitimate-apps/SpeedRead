import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch Library Persistence")
@MainActor
struct WatchLibraryTests {
    @Test func saveLoadRoundTrip() throws {
        let fixture = try fixtureStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let book = WatchBook(
            id: UUID(),
            title: "Watch Book",
            author: "Author",
            text: "one two three",
            lastReadIndex: 2,
            lastReadDate: Date(timeIntervalSince1970: 1_800_000_000),
            wordCount: 3,
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let original = WatchLibrary(books: [book], currentBookId: book.id)

        try fixture.store.save(original)

        #expect(fixture.store.load() == original)
    }

    @Test func corruptFileRecoversToEmptyLibrary() throws {
        let fixture = try fixtureStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("not json".utf8).write(to: fixture.store.fileURL)

        #expect(fixture.store.load() == .empty)
    }

    @Test func missingFileLoadsEmptyState() throws {
        let fixture = try fixtureStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        #expect(fixture.store.load() == .empty)
        #expect(fixture.store.load().books.isEmpty)
        #expect(fixture.store.load().currentBookId == nil)
    }

    @Test func unknownBookPositionUpdateDoesNothing() {
        var library = WatchLibrary.empty

        let updated = library.updatePosition(bookId: UUID(), index: 12)

        #expect(!updated)
        #expect(library == .empty)
    }

    private func fixtureStore() throws -> (store: WatchLibraryStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            WatchLibraryStore(fileURL: directory.appendingPathComponent("watchlibrary.json")),
            directory
        )
    }
}
