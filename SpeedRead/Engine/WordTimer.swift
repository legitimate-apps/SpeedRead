//  WordTimer.swift
import Foundation

struct WordTimer: Sendable {
    var wpm: Int

    var baseDelayMs: Int {
        60_000 / wpm
    }

    func delay(for word: String) -> Int {
        Int(Double(baseDelayMs) * Self.multiplier(for: word))
    }

    static func multiplier(for word: String) -> Double {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        var multiplier = 1.0

        if trimmed.count >= 8 {
            multiplier *= 1.3
        }
        if !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) {
            multiplier *= 1.8
        }

        switch word.last {
        case let c? where sentenceTerminators.contains(c):
            multiplier *= 2.0
        case let c? where clauseTerminators.contains(c):
            multiplier *= 1.5
        default:
            break
        }

        return multiplier
    }

    private static let sentenceTerminators: Set<Character> = [".", "?", "!"]
    private static let clauseTerminators: Set<Character> = [",", ";", ":", "\u{2014}", "\u{2013}"]
}
