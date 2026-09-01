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
        // TDD scaffold: the red test pins the operator-approved copy before the view adopts it.
        ""
    }

    static func speedValue(wpm: Int) -> String {
        // TDD scaffold: the red test pins the unit-bearing value used by the sheet.
        ""
    }

    static func currentChapter(
        in chapters: [ChapterMark],
        at wordIndex: Int
    ) -> ChapterMark? {
        // TDD scaffold: the red test pins which duplicate/boundary chapter receives the checkmark.
        nil
    }

    static func snappedWPM(_ value: Double) -> Int {
        // Existing behaviour intentionally remains unclamped for the red boundary test.
        Int((value / wpmStep).rounded() * wpmStep)
    }

    @discardableResult
    static func apply(_ value: Double, to engine: RSVPEngine) -> Int {
        let wpm = snappedWPM(value)
        engine.wpm = wpm
        return wpm
    }
}
