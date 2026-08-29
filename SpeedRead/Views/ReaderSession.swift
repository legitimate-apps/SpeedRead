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
    func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int, timestamp: Date)
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
        cachedWords = book.words
        paragraphs = ReaderParagraphizer.paragraphs(
            from: book.extractedText,
            allWords: cachedWords
        )
    }

    func clampedIndex(_ index: Int) -> Int {
        guard !cachedWords.isEmpty else { return 0 }
        return min(max(0, index), cachedWords.count - 1)
    }

    func scrollAnchorID(for index: Int) -> String {
        "word-\(index)"
    }

    func commitReadingPosition(
        _ index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: any ReadingPositionSyncing = WatchSyncService.shared,
        now: Date = Date()
    ) -> ReadingPositionCommit {
        let clamped = clampedIndex(index)
        book.lastReadWordIndex = clamped
        book.lastReadDate = now

        let didSave: Bool
        do {
            try saver.save()
            didSave = true
        } catch {
            didSave = false
        }

        sync.syncReadingPosition(
            bookId: book.id,
            bookTitle: book.title,
            wordIndex: clamped,
            timestamp: now
        )
        return ReadingPositionCommit(index: clamped, timestamp: now, didSave: didSave)
    }

    func handleWordTap(
        at index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: any ReadingPositionSyncing = WatchSyncService.shared,
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
        let modes = ReaderThemeMode.allCases
        let current = ReaderThemeMode(rawValue: rawValue) ?? .parchment
        guard let index = modes.firstIndex(of: current) else {
            return ReaderThemeMode.parchment.rawValue
        }
        return modes[(index + 1) % modes.count].rawValue
    }
}
