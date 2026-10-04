import Foundation
import Testing
@testable import SpeedRead

@Suite("Reader session")
@MainActor
struct ReaderSessionTests {
    @Test func loadsPersistedWordsAndParagraphCoordinatesOnce() {
        let book = makeBook(text: "alpha beta\n\ngamma delta")
        let session = ReaderSession()

        session.load(book: book)

        #expect(session.cachedWords == ["alpha", "beta", "gamma", "delta"])
        #expect(session.paragraphs.count == 2)
        if session.paragraphs.count == 2 {
            #expect(session.paragraphs[0].startIndex == 0)
            #expect(session.paragraphs[1].startIndex == 2)
        }

        book.extractedText = "replacement text must not retokenize"
        session.load(book: book)
        #expect(session.cachedWords == ["alpha", "beta", "gamma", "delta"])
    }

    @Test func emptyBookLoadsAsAnEmptySession() {
        let session = ReaderSession()
        session.load(book: makeBook(text: ""))

        #expect(session.cachedWords.isEmpty)
        #expect(session.paragraphs.isEmpty)
        #expect(session.clampedIndex(-10) == 0)
        #expect(session.clampedIndex(10) == 0)
    }

    @Test func singleWordBookClampsEveryPositionToZero() {
        let session = ReaderSession()
        session.load(book: makeBook(text: "only"))

        #expect(session.clampedIndex(-1) == 0)
        #expect(session.clampedIndex(0) == 0)
        #expect(session.clampedIndex(1) == 0)
    }

    @Test func positionClampsAtFirstAndLastWord() {
        let session = ReaderSession()
        session.load(book: makeBook(text: "zero one two"))

        #expect(session.clampedIndex(-1) == 0)
        #expect(session.clampedIndex(0) == 0)
        #expect(session.clampedIndex(2) == 2)
        #expect(session.clampedIndex(99) == 2)
    }

    @Test func tapCommitsClampedPositionAndRequestsAUniqueFlash() {
        let book = makeBook(text: "zero one two")
        let session = ReaderSession()
        let saver = RecordingPositionSaver()
        let sync = RecordingPositionSync()
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 101)
        session.load(book: book)

        let first = session.handleWordTap(
            at: 99,
            book: book,
            saver: saver,
            sync: sync,
            now: firstDate
        )
        let second = session.handleWordTap(
            at: 99,
            book: book,
            saver: saver,
            sync: sync,
            now: secondDate
        )

        #expect(first.commit == ReadingPositionCommit(index: 2, timestamp: firstDate, didSave: true))
        #expect(first.flash.wordIndex == 2)
        #expect(second.flash.wordIndex == 2)
        #expect(first.flash.id != second.flash.id)
        #expect(session.wordFlash == second.flash)
        #expect(book.lastReadWordIndex == 2)
        #expect(book.furthestReadWordIndex == 2)
        #expect(book.lastReadDate == secondDate)
        #expect(saver.saveCount == 2)
        #expect(sync.events.map(\.wordIndex) == [2, 2])
    }

    @Test func clearingAnOldFlashDoesNotCancelANewerTap() {
        let book = makeBook(text: "zero one")
        let session = ReaderSession()
        let saver = RecordingPositionSaver()
        let sync = RecordingPositionSync()
        session.load(book: book)
        let old = session.handleWordTap(at: 0, book: book, saver: saver, sync: sync).flash
        let new = session.handleWordTap(at: 1, book: book, saver: saver, sync: sync).flash

        session.clearWordFlash(old)
        #expect(session.wordFlash == new)
        session.clearWordFlash(new)
        #expect(session.wordFlash == nil)
    }

    @Test func saveFailureIsReportedWithoutDroppingThePositionOrSync() {
        let book = makeBook(text: "zero one two")
        let session = ReaderSession()
        let saver = RecordingPositionSaver(error: SaveFailure.expected)
        let sync = RecordingPositionSync()
        let now = Date(timeIntervalSince1970: 200)
        session.load(book: book)

        let result = session.commitReadingPosition(
            1,
            book: book,
            saver: saver,
            sync: sync,
            now: now
        )

        #expect(result == ReadingPositionCommit(index: 1, timestamp: now, didSave: false))
        #expect(book.lastReadWordIndex == 1)
        #expect(book.lastReadDate == now)
        #expect(book.furthestReadWordIndex == 1)
        #expect(saver.saveCount == 1)
        #expect(sync.events == [.init(
            bookID: book.id,
            title: book.title,
            wordIndex: 1,
            timestamp: now,
            furthestReadWordIndex: 1
        )])
    }

    @Test func emptyBookCommitUsesTheOnlyValidCoordinate() {
        let book = makeBook(text: "")
        let session = ReaderSession()
        let saver = RecordingPositionSaver()
        let sync = RecordingPositionSync()
        session.load(book: book)

        let result = session.commitReadingPosition(42, book: book, saver: saver, sync: sync)

        #expect(result.index == 0)
        #expect(book.lastReadWordIndex == 0)
        #expect(sync.events.map(\.wordIndex) == [0])
    }

    @Test func productionDefaultSyncDependencyDoesNotBlockLocalCommit() {
        let book = makeBook(text: "zero one")
        let session = ReaderSession()
        let saver = RecordingPositionSaver()
        let now = Date(timeIntervalSince1970: 250)
        session.load(book: book)

        let result = session.commitReadingPosition(1, book: book, saver: saver, now: now)

        #expect(result == ReadingPositionCommit(index: 1, timestamp: now, didSave: true))
        #expect(book.lastReadWordIndex == 1)
        #expect(saver.saveCount == 1)
    }

    @Test func initialAndRSVPDismissScrollsUseTheCurrentClampedPosition() {
        // The reader opens at the place (the word both devices show), not the reading marker.
        let book = makeBook(text: "zero one two")
        let session = ReaderSession()
        book.lastReadWordIndex = 1
        book.browseWordIndex = 99
        session.load(book: book)

        session.requestInitialScroll(for: book)
        #expect(session.consumePendingScroll() == 2)
        #expect(session.consumePendingScroll() == nil)

        book.browseWordIndex = -5
        session.reconcileRSVPDismiss(for: book)
        #expect(session.consumePendingScroll() == 0)
    }

    @Test func scrollAnchorIdentityPreservesTheUniversalWordIndex() {
        let session = ReaderSession()
        #expect(session.scrollAnchorID(for: 0) == "word-0")
        #expect(session.scrollAnchorID(for: 12_345) == "word-12345")
    }

    @Test func themesCycleInDisplayOrderAndRecoverFromInvalidStorage() {
        let session = ReaderSession()
        #expect(session.cycleTheme(from: ReaderThemeMode.parchment.rawValue) == ReaderThemeMode.sepia.rawValue)
        #expect(session.cycleTheme(from: ReaderThemeMode.sepia.rawValue) == ReaderThemeMode.night.rawValue)
        #expect(session.cycleTheme(from: ReaderThemeMode.night.rawValue) == ReaderThemeMode.parchment.rawValue)
        #expect(session.cycleTheme(from: "corrupt-value") == ReaderThemeMode.sepia.rawValue)
    }

    @Test(arguments: [-100, 1000])
    func readerCommitClampsBothBoundsBeforeSavingAndSyncing(index: Int) {
        // Mutation: bypass either bound at the coordinator commit call site.
        let book = makeBook(text: "zero one two")
        let session = ReaderSession()
        let saver = RecordingPositionSaver()
        let sync = RecordingPositionSync()
        session.load(book: book)
        let result = session.commitReadingPosition(index, book: book, saver: saver, sync: sync)
        let expected = index < 0 ? 0 : 2
        #expect(result.index == expected)
        #expect(book.lastReadWordIndex == expected)
        #expect(book.browseWordIndex == expected)
        #expect(saver.saveCount == 1)
        #expect(sync.events.map(\.wordIndex) == [expected])
    }

    private func makeBook(text: String) -> Book {
        Book(title: "Test", author: "Author", extractedText: text, sourceFileName: "test.txt")
    }
}

@MainActor
private final class RecordingPositionSaver: ReadingPositionSaving {
    private(set) var saveCount = 0
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func save() throws {
        saveCount += 1
        if let error { throw error }
    }
}

@MainActor
private final class RecordingPositionSync: ReadingPositionSyncing {
    struct Event: Equatable {
        let bookID: UUID
        let title: String
        let wordIndex: Int
        let timestamp: Date
        let furthestReadWordIndex: Int
    }

    private(set) var events: [Event] = []

    func syncReadingPosition(
        bookId: UUID,
        bookTitle: String,
        wordIndex: Int,
        timestamp: Date,
        furthestReadWordIndex: Int,
        didFinish: Bool,
        finishedAt: Date?
    ) {
        events.append(.init(
            bookID: bookId,
            title: bookTitle,
            wordIndex: wordIndex,
            timestamp: timestamp,
            furthestReadWordIndex: furthestReadWordIndex
        ))
    }
}

private enum SaveFailure: Error {
    case expected
}
