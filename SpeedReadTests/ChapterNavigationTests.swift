import Foundation
import Testing
@testable import SpeedRead

@Suite("Chapter navigation")
@MainActor
struct ChapterNavigationTests {
    @Test func boundariesAndDuplicateOffsetsHaveExactlyOneCurrentRow() {
        // Mutations: reverse sorting, choose first equal offset, use < instead of <=, mark every duplicate current.
        let navigation = ChapterNavigation(chapters: [
            .init(title: "Last", startWordIndex: 8),
            .init(title: "Empty", startWordIndex: 2),
            .init(title: "First", startWordIndex: 2),
            .init(title: "First", startWordIndex: 2)
        ])
        #expect(navigation.rows.map(\.title) == ["Empty", "First", "First", "Last"])
        for (word, expected) in [(0, nil), (2, 2), (7, 2), (8, 3), (99, 3)] as [(Int, Int?)] {
            let selected = navigation.rows.indices.filter { navigation.isCurrent(row: $0, at: word) }
            #expect(selected == expected.map { [$0] } ?? [])
            #expect(navigation.current(at: word) == expected.map { navigation.rows[$0] })
        }
        #expect(!navigation.isCurrent(row: -1, at: 8))
        #expect(!navigation.isCurrent(row: 4, at: 8))
        let empty = ChapterNavigation(chapters: [])
        #expect(empty.rows.isEmpty)
        #expect(empty.current(at: 0) == nil)
        #expect(!empty.isCurrent(row: 0, at: 0))
    }

    @Test func chapterBrowseAndRSVPScrubPreserveReadingMarkersUntilPlay() throws {
        // Mutations: commit a chapter jump, omit pending scroll/save, load RSVP at last-read, cache chapter at load instead of current engine index,
        // or return the reader to the reading marker instead of the place the scrub left.
        let book = Book(title: "Chapters", author: "", extractedText: "zero one two three four five", sourceFileName: "test.txt")
        book.lastReadWordIndex = 1
        book.ensurePositionMarkersInitialized()
        book.furthestReadWordIndex = 3
        let date = Date(timeIntervalSince1970: 100)
        book.lastReadDate = date
        let session = ReaderSession()
        session.load(book: book)
        let saver = ChapterSaver()
        let navigation = ChapterNavigation(chapters: [.init(title: "Opening", startWordIndex: 0), .init(title: "Ending", startWordIndex: 4)])
        #expect(session.browse(to: navigation.rows[1].startWordIndex, book: book, saver: saver))
        #expect(session.consumePendingScroll() == 4)
        #expect(book.browseWordIndex == 4)
        #expect(saver.count == 1)
        let engine = RSVPEngine()
        let presentation = RSVPPresentationSession()
        presentation.load(book: book, engine: engine, wpm: 300)
        #expect(engine.currentIndex == 4)
        #expect(navigation.current(at: engine.currentIndex)?.title == "Ending")
        let update = try #require(presentation.updateGesture(translationX: 400, at: 0, isPlaying: false, currentIndex: engine.currentIndex, wordCount: engine.totalWords, track: RSVPScrubTrack(words: presentation.cachedWords, advance: 20, availableWidth: 400)))
        engine.seek(to: update.targetIndex)
        #expect(navigation.current(at: engine.currentIndex)?.title == "Opening")
        let scrubbedTo = engine.currentIndex
        #expect(scrubbedTo < 4)
        #expect(presentation.recordBrowsePosition(scrubbedTo, book: book, saver: saver))
        #expect(presentation.close(engine: engine, book: book, saver: saver) == nil)
        #expect(book.lastReadWordIndex == 1)
        #expect(book.furthestReadWordIndex == 3)
        #expect(book.lastReadDate == date)
        session.reconcileRSVPDismiss(for: book)
        #expect(session.consumePendingScroll() == scrubbedTo)
        #expect(book.browseWordIndex == scrubbedTo)
    }

    @Test func distantBrowseResolvesContainingParagraphBeforeItsWordIsMounted() {
        // Mutations: use a word index as the lazy paragraph anchor, choose the next paragraph, omit bounds/empty handling.
        let book = Book(title: "Test", author: "", extractedText: "zero one\n\ntwo three four\n\nfive six", sourceFileName: "test.txt")
        let session = ReaderSession()
        session.load(book: book)
        for (word, paragraph) in [(-1, 0), (1, 0), (2, 2), (4, 2), (5, 5), (99, 5)] {
            #expect(session.paragraphAnchorID(for: word) == paragraph)
        }
        let empty = ReaderSession()
        empty.load(book: Book(title: "Empty", author: "", extractedText: "", sourceFileName: "empty.txt"))
        #expect(empty.paragraphAnchorID(for: 0) == nil)
    }

    @Test func failedBrowseSaveStillClampsAndNavigatesWithoutReading() {
        // Mutations: skip clamping either bound, suppress save error, change the reading commit on failure.
        let book = Book(title: "Test", author: "", extractedText: "one two three", sourceFileName: "test.txt")
        book.lastReadWordIndex = 1
        book.browseWordIndex = 1
        book.furthestReadWordIndex = 1
        let session = ReaderSession()
        session.load(book: book)
        let saver = ChapterSaver()
        saver.fail = true
        for (input, expected) in [(-10, 0), (100, 2)] {
            #expect(!session.browse(to: input, book: book, saver: saver))
            #expect(book.browseWordIndex == expected)
            #expect(session.consumePendingScroll() == expected)
            #expect(book.lastReadWordIndex == 1)
            #expect(book.furthestReadWordIndex == 1)
        }
        // A jump to the word already shown changes nothing, so there is nothing to save or send.
        let saves = saver.count
        #expect(session.browse(to: 2, book: book, saver: saver))
        #expect(saver.count == saves)
        #expect(session.consumePendingScroll() == 2)
    }
}

@MainActor
private final class ChapterSaver: ReadingPositionSaving {
    var count = 0
    var fail = false
    enum Failure: Error { case expected }
    func save() throws {
        count += 1
        if fail { throw Failure.expected }
    }
}
