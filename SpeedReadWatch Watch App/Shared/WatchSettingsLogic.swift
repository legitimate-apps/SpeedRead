import Foundation

/// Decisions owned by the watch reading-settings sheet.
///
/// This type deliberately lives outside `WatchSettingsView.swift`: attributable coverage is
/// measured per source file, so testable decisions beside SwiftUI markup make both look untested.
enum WatchSettingsLogic {
    static let wpmRange = 100...1_000
    static let wpmStep = 10.0

    enum Row: Equatable {
        case chapter
        case backToReadingPosition
        case speed
    }

    static func rows(hasChapters: Bool) -> [Row] {
        (hasChapters ? [.chapter] : []) + [.backToReadingPosition, .speed]
    }

    static func title(for row: Row) -> String {
        switch row {
        case .chapter: "Chapter"
        case .backToReadingPosition: "Back to where I was reading"
        case .speed: "Speed"
        }
    }

    static func speedValue(wpm: Int) -> String {
        "\(wpm) WPM"
    }

    static func currentChapter(
        in chapters: [ChapterMark],
        at wordIndex: Int
    ) -> ChapterMark? {
        ChapterIndex(chapters).chapter(containing: wordIndex)
    }

    static func snappedWPM(_ value: Double) -> Int {
        let snapped = Int((value / wpmStep).rounded() * wpmStep)
        return min(max(snapped, wpmRange.lowerBound), wpmRange.upperBound)
    }

    @discardableResult
    static func apply(_ value: Double, to engine: RSVPEngine) -> Int {
        let wpm = snappedWPM(value)
        engine.wpm = wpm
        return wpm
    }
}
