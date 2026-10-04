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

    @Test("crown math runs on the loaded token stream, not the stored word count")
    func crownMathUsesTheLoadedTokenStream() {
        // Whitespace sees 3 words, the canonical tokenizer 4. Legacy migrated books persisted
        // the whitespace count, so a stored wordCount is not a safe crown range.
        let session = WatchRSVPSession()

        let crownValue = session.load(book: makeBook(text: "self-aware zero one"), wpm: 300)

        #expect(session.wordCount == 4)
        #expect(crownValue == CrownSeek.crownValue(forWordIndex: 0, wordCount: 4))
        #expect(session.seek(toCrownValue: crownValue - 3) == CrownSeek.crownValue(forWordIndex: 3, wordCount: 4))
        #expect(session.engine.currentWord == "one")
    }

    @Test("the crown binding is left alone while playing and caught up on pause")
    func crownBindingIsPublishedOnlyWhenTheCrownIsLive() {
        // Publishing per word made watchOS rebuild the crown's detents across the whole book
        // on every word: MEASURED ~20% of a core at 1000 WPM on a 150k-word book.
        let session = WatchRSVPSession()
        _ = session.load(book: makeBook(text: "zero one two three four five"), wpm: 300)
        session.togglePlayback()
        session.engine.seek(to: 4)

        #expect(session.crownValueToPublish() == nil)

        session.togglePlayback()
        #expect(session.crownValueToPublish() == CrownSeek.crownValue(forWordIndex: 4, wordCount: 6))
        // The first detent after the pause moves one word from the visible one, not from where
        // the binding last stood before playback.
        session.seek(toCrownValue: CrownSeek.crownValue(forWordIndex: 4, wordCount: 6) + 1)
        #expect(session.engine.currentIndex == 3)
    }

    @Test func missingCurrentBookLeavesAnUnloadedEngine() {
        let session = WatchRSVPSession()

        let crownValue = session.load(book: nil, wpm: 300)

        #expect(crownValue == 0)
        #expect(session.wordCount == 0)
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

    @Test func pressingPlayEmitsAReadingCommit() throws {
        let book = makeBook(text: "zero one two", index: 0)
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 2)

        let commit = try #require(session.togglePlayback(
            book: book,
            now: Date(timeIntervalSince1970: 100)
        ))

        #expect(commit.wordIndex == 2)
        #expect(session.engine.state == .playing)
    }

    @Test func playbackAdvanceIsThrottledThenEmitsACommit() throws {
        let book = makeBook(text: "zero one two three", index: 0)
        let session = WatchRSVPSession()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = session.load(book: book, wpm: 300)
        _ = session.togglePlayback(book: book, now: start)
        session.engine.seek(to: 1)

        let early = session.commitPlaybackAdvanceIfNeeded(
            book: book,
            now: start.addingTimeInterval(4.9)
        )
        let due = try #require(session.commitPlaybackAdvanceIfNeeded(
            book: book,
            now: start.addingTimeInterval(5)
        ))

        #expect(early == nil)
        #expect(due.wordIndex == 1)
    }

    @Test func crownSeekUsesTheNamedDirectionMappingOnlyWhilePaused() {
        let session = WatchRSVPSession()
        _ = session.load(book: makeBook(text: "zero one two three"), wpm: 300)

        session.seek(toCrownValue: 0)
        #expect(session.engine.currentIndex == 3)
        session.togglePlayback()
        session.seek(toCrownValue: 3)
        #expect(session.engine.currentIndex == 3)
        session.togglePlayback()
    }

    @Test("stale crown: first detent after playback continues from the visible word")
    func firstCrownDetentAfterPlaybackDoesNotSnapBack() {
        let session = WatchRSVPSession()
        let staleCrownValue = session.load(book: makeBook(text: "zero one two three four five six eight", index: 2), wpm: 300)
        session.engine.seek(to: 6)

        session.seek(toCrownValue: staleCrownValue - 1)

        #expect(session.engine.currentIndex == 7)
    }

    @Test func closeSnapshotsTheVisibleIndexBeforeStopping() throws {
        let book = makeBook(text: "zero one two three")
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 2)
        _ = session.togglePlayback(book: book)

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
        _ = session.togglePlayback(book: book)

        let closeCommit = try #require(session.close(book: book))
        let duplicate = session.handleDisappear(book: book)

        #expect(closeCommit.wordIndex == 2)
        #expect(duplicate == nil)
    }

    @Test func disappearWithoutPlaybackDoesNotCommitBrowsing() {
        let book = makeBook(text: "zero one two")
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)
        session.engine.seek(to: 1)

        let commit = session.handleDisappear(book: book)

        #expect(commit == nil)
        #expect(session.engine.state == .idle)
    }

    @Test func selectingAChapterBrowsesWithoutCreatingAReadingCommit() {
        let originalReadDate = Date(timeIntervalSince1970: 500)
        let book = WatchBook(
            id: UUID(), title: "Watch Book", author: "Author",
            text: "zero one two three four", lastReadIndex: 1,
            lastReadDate: originalReadDate, browseWordIndex: 1,
            furthestReadWordIndex: 4, wordCount: 5,
            dateAdded: Date(timeIntervalSince1970: 1_000)
        )
        var library = WatchLibrary(books: [book], currentBookId: book.id)
        let session = WatchRSVPSession()
        _ = session.load(book: book, wpm: 300)

        let crownValue = WatchChapterSelection.browse(
            to: ChapterMark(title: "Later", startWordIndex: 3),
            in: book,
            session: session,
            library: &library
        )

        #expect(session.engine.currentIndex == 3)
        #expect(crownValue == CrownSeek.crownValue(forWordIndex: 3, wordCount: 5))
        #expect(library.currentBook?.browseWordIndex == 3)
        #expect(library.currentBook?.lastReadIndex == 1)
        #expect(library.currentBook?.lastReadDate == originalReadDate)
        #expect(library.currentBook?.furthestReadWordIndex == 4)
        #expect(session.handleDisappear(book: book) == nil)
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

    @Test func settingsListShowsChapterFirstOnlyWhenRealMarksExist() {
        #expect(WatchSettingsLogic.rows(hasChapters: false) == [
            .backToReadingPosition, .speed
        ])
        #expect(WatchSettingsLogic.rows(hasChapters: true) == [
            .chapter, .backToReadingPosition, .speed
        ])
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
