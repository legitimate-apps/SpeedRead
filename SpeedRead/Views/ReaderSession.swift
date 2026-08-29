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
        // Deliberately inert TDD scaffold. The behavior lands after its tests.
    }

    func clampedIndex(_ index: Int) -> Int {
        0
    }

    func scrollAnchorID(for index: Int) -> String {
        ""
    }

    func commitReadingPosition(
        _ index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: any ReadingPositionSyncing = WatchSyncService.shared,
        now: Date = Date()
    ) -> ReadingPositionCommit {
        ReadingPositionCommit(index: 0, timestamp: now, didSave: false)
    }

    func handleWordTap(
        at index: Int,
        book: Book,
        saver: any ReadingPositionSaving,
        sync: any ReadingPositionSyncing = WatchSyncService.shared,
        now: Date = Date()
    ) -> ReaderTapOutcome {
        let commit = ReadingPositionCommit(index: 0, timestamp: now, didSave: false)
        let flash = ReaderWordFlash(id: 0, wordIndex: 0)
        return ReaderTapOutcome(commit: commit, flash: flash)
    }

    func clearWordFlash(_ flash: ReaderWordFlash) {}

    func requestInitialScroll(for book: Book) {}

    func reconcileRSVPDismiss(for book: Book) {}

    func consumePendingScroll() -> Int? {
        nil
    }

    func cycleTheme(from rawValue: String) -> String {
        rawValue
    }
}
