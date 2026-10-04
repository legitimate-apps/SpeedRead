//  LongWord.swift
import CoreFoundation
import Foundation

/// What RSVP does with a token too long to read at a glance.
///
/// A long word made of letters is shown as hyphenated pieces, each with its own pivot and beat
/// (Spritz's rule: past thirteen letters, two thirds of readers preferred the split). A long
/// token that is not a word — a URL, an address, an ISBN — is never split: it is shown whole and
/// centered, and held longer. The pieces are presentation only; the token keeps one word index,
/// so positions and sync never see them.
nonisolated enum LongWord {
    enum Kind: Equatable, Sendable {
        case ordinary
        case splittable
        case literal
    }

    static let maxPieceLength = 13
    /// No word is longer than this; a longer run of letters is junk or embedded data from the
    /// file, and splitting it would cost time in the square of its length on the main actor.
    static let maxSplittableLength = 64

    static func kind(of word: String) -> Kind {
        let core = coreRange(of: word)
        let letters = word[core]
        guard letters.count > maxPieceLength else { return .ordinary }
        guard letters.count <= maxSplittableLength else { return .literal }
        return letters.allSatisfy { $0.isLetter || joiners.contains($0) || dashes.contains($0) }
            ? .splittable : .literal
    }

    static func pieces(of word: String) -> [String] {
        guard kind(of: word) == .splittable else { return [word] }
        let characters = Array(word)
        let breaks = breakOpportunities(in: word, characters: characters)
        var pieces: [String] = []
        var start = 0
        // A hyphen is added to most pieces, so each piece has room for twelve letters.
        let capacity = maxPieceLength - 1
        while characters.count - start > maxPieceLength {
            let remaining = characters.count - start
            let count = (remaining + capacity - 1) / capacity
            let ideal = start + remaining / count
            let candidates = breaks.filter { end, addsHyphen in
                end > start && end < characters.count
                    && end - start + (addsHyphen ? 1 : 0) <= maxPieceLength
                    && characters.count - end >= 3
            }
            let chosen = candidates.min { lhs, rhs in
                let (l, r) = (abs(lhs.key - ideal), abs(rhs.key - ideal))
                return l == r ? lhs.key > rhs.key : l < r
            }
            let end = chosen?.key ?? min(ideal, start + capacity)
            let addsHyphen = chosen?.value ?? true
            pieces.append(String(characters[start..<end]) + (addsHyphen ? "-" : ""))
            start = end
        }
        pieces.append(String(characters[start...]))
        return pieces
    }

    // MARK: - Private

    private static let joiners: Set<Character> = ["'", "\u{2019}"]
    private static let dashes: Set<Character> = ["-", "\u{2014}", "\u{2013}"]

    /// The token without the punctuation around it: quotes, brackets, trailing commas.
    private static func coreRange(of word: String) -> Range<String.Index> {
        let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = word.firstIndex(where: isCore),
              let last = word.lastIndex(where: isCore) else {
            return word.startIndex..<word.startIndex
        }
        return first..<word.index(after: last)
    }

    /// Character offsets a piece may end at, each with whether the cut needs a hyphen drawn.
    /// A cut right after a dash already shows its own mark.
    private static func breakOpportunities(in word: String, characters: [Character]) -> [Int: Bool] {
        var breaks: [Int: Bool] = [:]
        for (offset, character) in characters.enumerated() where dashes.contains(character) {
            breaks[offset + 1] = false
        }
        for offset in hyphenationPoints(in: word) where breaks[offset] == nil {
            breaks[offset] = true
        }
        return breaks
    }

    /// Syllable boundaries from the system hyphenator, as character offsets.
    private static func hyphenationPoints(in word: String) -> [Int] {
        guard let locale = hyphenationLocale else { return [] }
        let string = word as NSString as CFString
        let length = CFStringGetLength(string)
        var points: [Int] = []
        var location = length
        while location > 0 {
            let found = CFStringGetHyphenationLocationBeforeIndex(
                string, location, CFRange(location: 0, length: length), 0, locale, nil
            )
            guard found != kCFNotFound, found > 0, found < location else { break }
            if let index = String.Index(utf16Offset: found, in: word).samePosition(in: word) {
                points.append(word.distance(from: word.startIndex, to: index))
            }
            location = found
        }
        return points
    }

    // CFLocale is immutable once created.
    nonisolated(unsafe) private static let hyphenationLocale: CFLocale? = {
        for identifier in [Locale.current.identifier, "en_US"] {
            let locale = NSLocale(localeIdentifier: identifier) as CFLocale
            if CFStringIsHyphenationAvailableForLocale(locale) {
                return locale
            }
        }
        return nil
    }()
}
