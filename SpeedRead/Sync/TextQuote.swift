import Foundation

/// A passage expressed as the book's own words: `exact` is the whole source words of the
/// passage, and `prefix`/`suffix` are up to eight words of context on each side — the W3C
/// TextQuoteSelector shape. The library server resolves the same quote against its copy of the
/// book, so a highlight or bookmark made here lands on the same words in every other reader.
///
/// A bookmark is a one-word quote. Another reader may send an empty `exact` for a point, with
/// the context alone carrying the place.
nonisolated struct TextQuote: Codable, Hashable, Sendable {
    let exact: String
    let prefix: String
    let suffix: String

    static let contextWords = ReadingAnchor.contextWords
    static let maximumExactScalars = 4_000

    init(exact: String, prefix: String, suffix: String) {
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }

    /// The server sends `null` for empty context at the edges of a book.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exact = try container.decodeIfPresent(String.self, forKey: .exact) ?? ""
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
    }

    /// The quote as the server will accept it, or nil when it cannot be sent at all: a passage
    /// over the server's limit, or one that folds to nothing. Context over the limit is trimmed by
    /// whole words from the far end instead.
    func wireSafe() -> TextQuote? {
        guard exact.unicodeScalars.count <= Self.maximumExactScalars, !ReadingAnchor.fold(exact).isEmpty
        else { return nil }
        return TextQuote(
            exact: exact,
            prefix: ReadingAnchor.trimmed(prefix, keepingEnd: true),
            suffix: ReadingAnchor.trimmed(suffix, keepingEnd: false)
        )
    }
}

nonisolated extension AnchoredText {
    // MARK: Building

    /// The quote for the tokens `start...end`, widened to whole source words so a range that
    /// splits a hyphenated word still quotes words another reader has.
    func quote(fromToken start: Int, toToken end: Int) -> TextQuote? {
        guard start <= end, let first = word(containingToken: start), let last = word(containingToken: end)
        else { return nil }
        return TextQuote(
            exact: words[first...last].joined(separator: " "),
            prefix: words[max(0, first - TextQuote.contextWords)..<first].joined(separator: " "),
            suffix: words[(last + 1)..<min(words.count, last + 1 + TextQuote.contextWords)].joined(separator: " ")
        )
    }

    // MARK: Resolving

    /// The tokens `quote` names, or nil when it cannot be placed with confidence. With no
    /// `fraction` a match must be unique; with one, the nearest match within the drift window
    /// wins. Context is tried in full, then one side at a time, since an edited sentence on one
    /// side of a passage should not lose it.
    func resolve(_ quote: TextQuote, near fraction: Double?) -> ClosedRange<Int>? {
        guard !folded.isEmpty else { return nil }
        let core = ReadingAnchor.fold(quote.exact)
        let before = ReadingAnchor.fold(quote.prefix), after = ReadingAnchor.fold(quote.suffix)
        if core.isEmpty { return resolvePoint(before: before, after: after, near: fraction) }

        let needles: [(bytes: String, coreOffset: Int, partial: Bool)] = [
            (before + core + after, before.utf8.count, false),
            (before + core, before.utf8.count, true),
            (core + after, 0, true),
        ]
        for needle in needles {
            if needle.partial, needle.bytes.utf8.count < Self.minimumPartialNeedle { continue }
            switch match(Array(needle.bytes.utf8), near: fraction) {
            case .none: continue
            case .refused: return nil
            case .at(let hit):
                let startByte = hit + needle.coreOffset
                guard let first = lastIndex(in: wordStarts, atOrBelow: startByte),
                      let last = lastIndex(in: wordStarts, atOrBelow: startByte + core.utf8.count - 1)
                else { return nil }
                let end = last + 1 < words.count ? wordFirstTokens[last + 1] - 1 : tokenCount - 1
                return wordFirstTokens[first]...max(wordFirstTokens[first], end)
            }
        }
        return nil
    }

    /// A point with no words of its own: the first word after its context.
    private func resolvePoint(before: String, after: String, near fraction: Double?) -> ClosedRange<Int>? {
        let needle = before + after
        guard !before.isEmpty, !after.isEmpty, needle.utf8.count >= Self.minimumPartialNeedle,
              case .at(let hit) = match(Array(needle.utf8), near: fraction),
              let w = lastIndex(in: wordStarts, atOrBelow: hit + before.utf8.count)
        else { return nil }
        return wordFirstTokens[w]...wordFirstTokens[w]
    }

    private enum Match { case none, refused, at(Int) }

    /// No match moves on to a shorter needle. An ambiguous or far-off match is refused outright:
    /// less context cannot make the choice safer.
    private func match(_ needle: [UInt8], near fraction: Double?) -> Match {
        let hits = occurrences(of: needle)
        guard let firstHit = hits.first else { return .none }
        guard let fraction else { return hits.count == 1 ? .at(firstHit) : .refused }
        let expected = Int(Double(folded.count) * min(max(fraction, 0), 1))
        let drift = max(Int(Double(folded.count) * Self.maximumDrift), Self.minimumDriftBytes)
        let nearest = hits.min { abs($0 - expected) < abs($1 - expected) }!
        return abs(nearest - expected) <= drift ? .at(nearest) : .refused
    }
}
