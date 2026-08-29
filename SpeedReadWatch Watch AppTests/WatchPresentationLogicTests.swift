import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch RSVP session")
@MainActor
struct WatchRSVPSessionTests {
    @Test func loadsTheCurrentBookAtItsPersistedPositionAndSpeed() {
        let book = makeBook(text: "zero one two", index: 2)
        let session = WatchRSVPSession()

        let crownValue = session.load(book: book, wpm: 430)

        #expect(session.engine.currentIndex == 2)
        #expect(session.engine.currentWord == "two")
        #expect(session.engine.wpm == 430)
        #expect(crownValue == CrownSeek.crownValue(forWordIndex: 2, wordCount: 3))
    }

    @Test func missingCurrentBookLeavesAnUnloadedEngine() {
        let session = WatchRSVPSession()

        let crownValue = session.load(book: nil, wpm: 300)

        #expect(crownValue == 0)
        #expect(!session.engine.isLoaded)
        #expect(session.engine.state == .idle)
    }

    @Test func tapAndAccessibleControlShareTheSamePlaybackDecision() {
        let session = WatchRSVPSession()
        _ = session.load(book: makeBook(text: "zero one"), wpm: 300)

        session.togglePlayback()
        #expect(session.engine.state == .playing)
        session.togglePlayback()
        #expect(session.engine.state == .paused)
    }

    @Test func openingSettingsPausesPlayback() {
        let session = WatchRSVPSession()
        _ = session.load(book: makeBook(text: "zero one"), wpm: 300)
        session.togglePlayback()

        session.prepareForSettings()

        #expect(session.engine.state == .paused)
    }

    @Test func crownSeekUsesTheNamedDirectionMappingOnlyWhilePaused() {
        let session = WatchRSVPSession()
        _ = session.load(book: makeBook(text: "zero one two three"), wpm: 300)

        session.seek(toCrownValue: 0, wordCount: 4)
        #expect(session.engine.currentIndex == 3)
        session.togglePlayback()
        session.seek(toCrownValue: 3, wordCount: 4)
        #expect(session.engine.currentIndex == 3)
        session.togglePlayback()
    }

    @Test func closeSnapshotsTheVisibleIndexBeforeStopping() throws {
        let book = makeBook(text: "zero one two three")
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 2)
        session.engine.play()

        let commit = try #require(session.close(book: book))

        #expect(commit == .init(bookId: book.id, bookTitle: book.title, wordIndex: 2))
        #expect(session.engine.state == .idle)
        #expect(session.engine.currentIndex == 0)
    }

    @Test("close followed by onDisappear cannot overwrite the saved position with zero")
    func closeThenDisappearEmitsOnlyOnePositionCommit() throws {
        let book = makeBook(text: "zero one two")
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 2)

        let closeCommit = try #require(session.close(book: book))
        let duplicate = session.handleDisappear(book: book)

        #expect(closeCommit.wordIndex == 2)
        #expect(duplicate == nil)
    }

    @Test func disappearCommitsAVisibleLoadedPositionThenStops() throws {
        let book = makeBook(text: "zero one two")
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 1)

        let commit = try #require(session.handleDisappear(book: book))

        #expect(commit.wordIndex == 1)
        #expect(session.engine.state == .idle)
    }

    private func makeBook(text: String, index: Int = 0) -> WatchBook {
        WatchBook(
            id: UUID(),
            title: "Watch Book",
            author: "Author",
            text: text,
            lastReadIndex: index,
            lastReadDate: nil,
            wordCount: text.split(whereSeparator: \.isWhitespace).count,
            dateAdded: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@Suite("Watch presentation characterization")
@MainActor
struct WatchPresentationCharacterizationTests {
    @Test("Characterization: detail action title follows persisted reading position")
    func detailActionTitle() {
        #expect(WatchBookDetailLogic.readingActionTitle(lastReadIndex: 0) == "Read")
        #expect(WatchBookDetailLogic.readingActionTitle(lastReadIndex: 1) == "Continue Reading")
    }

    @Test("Characterization: selecting a detail book makes it current")
    func selectingBook() {
        let first = makeBook(title: "First", added: 1)
        let second = makeBook(title: "Second", added: 2)
        var library = WatchLibrary(books: [first, second], currentBookId: first.id)

        WatchBookDetailLogic.select(second, in: &library)

        #expect(library.currentBookId == second.id)
    }

    @Test("Characterization: removing the selected detail picks the newest survivor")
    func removingSelectedBook() {
        let old = makeBook(title: "Old", added: 1)
        let newest = makeBook(title: "Newest", added: 3)
        let selected = makeBook(title: "Selected", added: 2)
        var library = WatchLibrary(books: [old, newest, selected], currentBookId: selected.id)

        WatchBookDetailLogic.remove(selected, from: &library)

        #expect(library.currentBookId == newest.id)
        #expect(!library.books.contains(selected))
    }

    @Test("Characterization: library presentation state prioritizes receipt over content")
    func libraryStatePrecedence() {
        let book = makeBook(title: "Book", added: 1)

        #expect(WatchLibraryLogic.state(isReceiving: true, library: .empty) == .receiving)
        #expect(WatchLibraryLogic.state(isReceiving: false, library: .empty) == .empty)
        #expect(WatchLibraryLogic.state(
            isReceiving: false,
            library: .init(books: [book], currentBookId: book.id)
        ) == .books)
    }

    @Test("Characterization: list deletion indexes the visible newest-first order")
    func deletingVisibleRows() {
        let old = makeBook(title: "Old", added: 1)
        let middle = makeBook(title: "Middle", added: 2)
        let newest = makeBook(title: "Newest", added: 3)
        var library = WatchLibrary(books: [old, middle, newest], currentBookId: old.id)

        WatchLibraryLogic.removeBooks(at: IndexSet(integer: 0), from: &library)

        #expect(!library.books.contains(newest))
        #expect(library.books.contains(old))
        #expect(library.books.contains(middle))
    }

    @Test("Characterization: settings snap to ten-WPM increments")
    func settingsSnap() {
        #expect(WatchSettingsLogic.snappedWPM(344) == 340)
        #expect(WatchSettingsLogic.snappedWPM(346) == 350)
    }

    @Test("Characterization: applying watch settings updates the engine")
    func settingsApply() {
        let engine = RSVPEngine()
        engine.load(words: ["one"], startingAt: 0)

        let persisted = WatchSettingsLogic.apply(447, to: engine)

        #expect(persisted == 450)
        #expect(engine.wpm == 450)
    }

    private func makeBook(title: String, added: TimeInterval) -> WatchBook {
        WatchBook(
            id: UUID(),
            title: title,
            author: "Author",
            text: "one two",
            lastReadIndex: 0,
            lastReadDate: nil,
            wordCount: 2,
            dateAdded: Date(timeIntervalSince1970: added)
        )
    }
}
