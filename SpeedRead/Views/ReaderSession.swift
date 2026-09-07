import Foundation
import Observation
import SwiftData

@MainActor
protocol ReadingPositionSaving {
    func save() throws
}

extension ModelContext: ReadingPositionSaving {}

@MainActor
protocol ReadingPositionSyncing {
    func syncReadingPosition(
        bookId: UUID,
        bookTitle: String,
        wordIndex: Int,
        timestamp: Date,
        furthestReadWordIndex: Int
    )
}

extension WatchSyncService: ReadingPositionSyncing {}

struct ReadingPositionCommit: Equatable {
    let index: Int
    let timestamp: Date
    let didSave: Bool
}

struct ReaderWordFlash: Equatable, Identifiable {
    let id: Int
    let wordIndex: Int
}

struct ReaderTapOutcome: Equatable {
    let commit: ReadingPositionCommit
    let flash: ReaderWordFlash
}

@MainActor
extension ReadingPositionCoordinator {

    static func commit(
        _ index: Int,
        wordCount: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date(),
        didFinish: Bool = false
    ) -> ReadingPositionCommit {
        let clamped = clampedIndex(index, wordCount: wordCount)
        book.ensurePositionMarkersInitialized()
        book.lastReadWordIndex = clamped
        book.lastReadDate = now
        book.finishedAt = didFinish && wordCount > 0 && clamped == wordCount - 1
            ? (book.finishedAt ?? now) : nil
        book.browseWordIndex = clamped
        book.furthestReadWordIndex = max(book.furthestReadWordIndex, clamped)

        let didSave: Bool
        do {
            try saver.save()
            didSave = true
        } catch {
            didSave = false
        }

        let positionSync = sync ?? WatchSyncService.shared
        positionSync.syncReadingPosition(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: clamped,
            timestamp: now,
            furthestReadWordIndex: book.furthestReadWordIndex
        )
        return ReadingPositionCommit(index: clamped, timestamp: now, didSave: didSave)
    }
}

@Observable
@MainActor
final class ReaderSession {
    private(set) var cachedWords: [String] = []
    private(set) var paragraphs: [ReaderParagraph] = []
    private(set) var pendingScrollIndex: Int?
    private(set) var wordFlash: ReaderWordFlash?

    private var nextFlashID = 0
    private var hasLoaded = false

    func load(book: Book) {
        guard !hasLoaded else { return }
        hasLoaded = true
        book.ensureTokensCached()
        book.ensurePositionMarkersInitialized()
        cachedWords = book.words
        paragraphs = ReaderParagraphizer.paragraphs(
            from: book.extractedText,
            allWords: cachedWords
        )
    }

    func clampedIndex(_ index: Int) -> Int {
        ReadingPositionCoordinator.clampedIndex(index, wordCount: cachedWords.count)
    }

    func scrollAnchorID(for index: Int) -> String {
        "word-\(index)"
    }

    func commitReadingPosition(
        _ index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReadingPositionCommit {
        ReadingPositionCoordinator.commit(
            index,
            wordCount: cachedWords.count,
            book: book,
            saver: saver,
            sync: sync,
            now: now
        )
    }

    func handleWordTap(
        at index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: (any ReadingPositionSyncing)? = nil,
        now: Date = Date()
    ) -> ReaderTapOutcome {
        let commit = commitReadingPosition(
            index,
            book: book,
            saver: saver,
            sync: sync,
            now: now
        )
        nextFlashID += 1
        let flash = ReaderWordFlash(id: nextFlashID, wordIndex: commit.index)
        wordFlash = flash
        return ReaderTapOutcome(commit: commit, flash: flash)
    }

    func clearWordFlash(_ flash: ReaderWordFlash) {
        guard wordFlash == flash else { return }
        wordFlash = nil
    }

    func requestInitialScroll(for book: Book) {
        pendingScrollIndex = clampedIndex(book.lastReadWordIndex)
    }

    func reconcileRSVPDismiss(for book: Book) {
        pendingScrollIndex = clampedIndex(book.lastReadWordIndex)
    }

    func consumePendingScroll() -> Int? {
        defer { pendingScrollIndex = nil }
        return pendingScrollIndex
    }

    func cycleTheme(from rawValue: String) -> String {
        let current = ReaderThemeMode(rawValue: rawValue) ?? .parchment
        switch current {
        case .parchment:
            return ReaderThemeMode.sepia.rawValue
        case .sepia:
            return ReaderThemeMode.night.rawValue
        case .night:
            return ReaderThemeMode.parchment.rawValue
        }
    }
}
