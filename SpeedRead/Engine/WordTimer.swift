//  WordTimer.swift
import Foundation

struct WordTimer {
    var wpm: Int

    var baseDelayMs: Int {
        60_000 / wpm
    }

    func delay(for word: String) -> Int {
        var multiplier = 1.0

        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)

        // Long word check (8+ alphanumeric characters)
        if trimmed.count >= 8 {
            multiplier *= 1.3
        }

        // Number check (entire word is numeric)
        if trimmed.allSatisfy({ $0.isNumber }) && !trimmed.isEmpty {
            multiplier *= 1.8
        }

        // Sentence-ending punctuation
        if word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!") {
            multiplier *= 2.0
        }
        // Clause punctuation (only if not already sentence-ending)
        else if word.hasSuffix(",") || word.hasSuffix(";") || word.hasSuffix(":") || word.hasSuffix("\u{2014}") || word.hasSuffix("\u{2013}") {
            multiplier *= 1.5
        }

        return Int(Double(baseDelayMs) * multiplier)
    }
}
