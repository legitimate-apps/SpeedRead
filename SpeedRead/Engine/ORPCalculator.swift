//  ORPCalculator.swift
import Foundation

enum ORPCalculator {

    struct WordSegments: Equatable, Sendable {
        let before: String
        let focus: String
        let after: String
    }

    static func orpIndex(for word: String) -> Int {
        guard !word.isEmpty else { return 0 }

        let leadingPunctCount = word.prefix(while: \.isPunctuationOrSymbol).count
        let strippedLength = word.dropFirst(leadingPunctCount)
            .prefix(while: \.isWordCharacter)
            .count

        guard strippedLength > 0 else { return 0 }
        return leadingPunctCount + bucket(for: strippedLength)
    }

    static func segments(for word: String) -> WordSegments {
        guard !word.isEmpty else {
            return WordSegments(before: "", focus: "", after: "")
        }

        let count = word.count
        let clampedIdx = min(orpIndex(for: word), count - 1)
        let focusStart = word.index(word.startIndex, offsetBy: clampedIdx)
        let focusEnd = word.index(after: focusStart)

        return WordSegments(
            before: String(word[..<focusStart]),
            focus: String(word[focusStart..<focusEnd]),
            after: String(word[focusEnd...])
        )
    }

    private static func bucket(for alphaLength: Int) -> Int {
        switch alphaLength {
        case 0...1:   return 0
        case 2...5:   return 1
        case 6...9:   return 2
        case 10...13: return 3
        default:      return 4
        }
    }
}

private extension Character {
    var isPunctuationOrSymbol: Bool {
        !isLetter && !isNumber
    }

    var isWordCharacter: Bool {
        isLetter || isNumber || self == "'" || self == "-"
    }
}
