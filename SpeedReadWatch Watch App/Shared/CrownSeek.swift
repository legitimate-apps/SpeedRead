import Foundation

/// Maps Digital Crown rotation onto a word index for the watch RSVP reader.
///
/// `digitalCrownRotation` hands us a value that rises as the crown turns one way and falls as it
/// turns the other. Which of those two directions a reader experiences as "forward through the
/// book" is a product decision, not something the API states — so it is stated here, pinned by a
/// test, and changed in one place rather than inside a view modifier.
enum CrownSeek {

    /// Highest addressable word index for a book of `wordCount` words.
    static func maxIndex(wordCount: Int) -> Int {
        max(0, wordCount - 1)
    }

    /// Upper bound handed to `digitalCrownRotation(_:from:through:by:)`.
    /// Never zero — a zero-width range gives the crown nothing to travel over.
    static func crownUpperBound(wordCount: Int) -> Double {
        max(1, Double(maxIndex(wordCount: wordCount)))
    }

    /// Crown value -> word index.
    ///
    /// Inverted on purpose. The crown's bound value rises as the crown turns the way that reads
    /// as *backwards* through a book, so a higher crown value maps to an earlier word. Reported by
    /// the operator 2026-08-29 against the previous direct mapping.
    static func wordIndex(forCrownValue value: Double, wordCount: Int) -> Int {
        let top = maxIndex(wordCount: wordCount)
        guard top > 0 else { return 0 }
        let raw = value.isFinite ? Int(value.rounded()) : 0
        return top - min(max(raw, 0), top)
    }

    /// Word index -> crown value. Must be the exact inverse of `wordIndex(forCrownValue:wordCount:)`
    /// so that seeding the crown on appear, and following the engine during playback, cannot drift.
    static func crownValue(forWordIndex index: Int, wordCount: Int) -> Double {
        let top = maxIndex(wordCount: wordCount)
        guard top > 0 else { return 0 }
        return Double(top - min(max(index, 0), top))
    }
}
