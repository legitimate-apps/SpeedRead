//  ORPCalculator.swift
import Foundation

enum ORPCalculator {

    struct WordSegments {
        let before: String
        let focus: String
        let after: String
    }

    static func orpIndex(for word: String) -> Int {
        guard !word.isEmpty else { return 0 }

        let chars = Array(word)
        let leadingPunctCount = chars.prefix(while: { !$0.isLetter && !$0.isNumber }).count
        let strippedLength = chars.suffix(from: leadingPunctCount)
            .prefix(while: { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" })
            .count

        guard strippedLength > 0 else { return 0 }

        let rawORPIndex = orpBucket(for: strippedLength)
        return leadingPunctCount + rawORPIndex
    }

    static func segments(for word: String) -> WordSegments {
        guard !word.isEmpty else {
            return WordSegments(before: "", focus: "", after: "")
        }

        let idx = orpIndex(for: word)
        let chars = Array(word)
        let clampedIdx = min(idx, chars.count - 1)

        let before = String(chars[..<clampedIdx])
        let focus = String(chars[clampedIdx])
        let after = clampedIdx + 1 < chars.count ? String(chars[(clampedIdx + 1)...]) : ""

        return WordSegments(before: before, focus: focus, after: after)
    }

    private static func orpBucket(for alphaLength: Int) -> Int {
        switch alphaLength {
        case 0:     return 0
        case 1:     return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default:    return 4
        }
    }
}
