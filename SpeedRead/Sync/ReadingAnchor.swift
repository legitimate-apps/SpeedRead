import Foundation

/// A position expressed as the reader's own words, so it survives different tokenizers: `text`
/// is the whole source word at the position, and `before`/`after` are up to eight words of
/// context on each side. A sync server resolves the same shape against its copy of the book.
///
/// Words are the text split on whitespace — `BookTokenizer`'s first step — so a hyphen-split
/// token maps back to the source word it came from. Matching folds both sides the way the
/// server does (`fold`) and ignores whitespace entirely, so word boundaries that two
/// extractors disagree about do not prevent a match.
nonisolated struct ReadingAnchor: Codable, Hashable, Sendable {
    let text: String
    let before: String
    let after: String

    static let contextWords = 8

    /// Builds the anchor for one position without preparing the whole book for matching:
    /// one split and one token count per word, no folding.
    static func build(text: String, tokenIndex: Int) -> ReadingAnchor? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard tokenIndex >= 0 else { return nil }
        var firstToken = 0
        for w in words.indices {
            firstToken += BookTokenizer.splitHyphens(words[w]).count
            if tokenIndex < firstToken { return ReadingAnchor(words: words, at: w) }
        }
        return nil
    }

    init(text: String, before: String, after: String) {
        self.text = text
        self.before = before
        self.after = after
    }

    init(words: [Substring], at w: Int) {
        text = String(words[w])
        before = words[max(0, w - Self.contextWords)..<w].joined(separator: " ")
        after = words[(w + 1)..<min(words.count, w + 1 + Self.contextWords)].joined(separator: " ")
    }

    /// The server sends `null` for empty context at the edges of a book.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        before = try container.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try container.decodeIfPresent(String.self, forKey: .after) ?? ""
    }

    /// The anchor as the server will accept it, or nil when it cannot be sent at all. The server
    /// rejects the whole push (400) for a `text` over 200 scalars or that folds to nothing, and for
    /// context over 600 — so context is trimmed by whole words from the far end instead.
    func wireSafe() -> ReadingAnchor? {
        guard text.unicodeScalars.count <= Self.maximumTextScalars, !Self.fold(text).isEmpty else { return nil }
        return ReadingAnchor(
            text: text,
            before: Self.trimmed(before, keepingEnd: true),
            after: Self.trimmed(after, keepingEnd: false)
        )
    }

    static let maximumTextScalars = 200
    static let maximumContextScalars = 600

    static func trimmed(_ context: String, keepingEnd: Bool) -> String {
        var words = context.split(separator: " ")
        while words.joined(separator: " ").unicodeScalars.count > maximumContextScalars {
            if keepingEnd { words.removeFirst() } else { words.removeLast() }
        }
        return words.joined(separator: " ")
    }

    func resolve(in text: String, near fraction: Double) -> Int? {
        AnchoredText(text).resolve(self, near: fraction)
    }

    // MARK: Folding

    /// The sync server's fold, scalar by scalar, so both sides compare identical byte strings:
    /// drop whitespace, soft hyphens and zero-width characters; fold dash and curly-quote
    /// variants to ASCII; otherwise decompose (NFKD), drop nonspacing marks, and lowercase.
    /// Diacritics are ignored on purpose — precomposed and decomposed forms differ between
    /// EPUB sources — so "Café", "Cafe\u{301}" and "CAFE" all fold to "cafe".
    static func fold(_ string: some StringProtocol) -> String {
        if string.utf8.allSatisfy({ $0 < 0x80 }) {
            return String(decoding: string.utf8.lazy.filter { !asciiWhitespace.contains($0) }.map(asciiLowercased), as: UTF8.self)
        }
        var folded = ""
        for scalar in string.unicodeScalars {
            if scalar.isASCII {
                let byte = UInt8(scalar.value)
                if !asciiWhitespace.contains(byte) { folded.unicodeScalars.append(Unicode.Scalar(asciiLowercased(byte))) }
                continue
            }
            if scalar.properties.isWhitespace || removedScalars.contains(scalar.value) { continue }
            if let replacement = foldedScalars[scalar.value] {
                folded.unicodeScalars.append(replacement)
                continue
            }
            var unmarked = String.UnicodeScalarView()
            for part in String(scalar).decomposedStringWithCompatibilityMapping.unicodeScalars
            where part.properties.generalCategory != .nonspacingMark {
                unmarked.append(part)
            }
            folded += String(unmarked).lowercased()
        }
        return folded
    }

    private static let asciiWhitespace: Set<UInt8> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20]
    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte | 0x20 : byte
    }

    private static let removedScalars: Set<UInt32> = [0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]
    private static let foldedScalars: [UInt32: Unicode.Scalar] = {
        var map: [UInt32: Unicode.Scalar] = [:]
        for dash: UInt32 in [0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212] { map[dash] = "-" }
        for quote: UInt32 in [0x2018, 0x2019, 0x201A, 0x201B] { map[quote] = "'" }
        for quote: UInt32 in [0x201C, 0x201D, 0x201E, 0x201F] { map[quote] = "\"" }
        return map
    }()
}

/// A book prepared for anchors: its source words, each word's first token, and the whole text
/// folded into one whitespace-free byte string. Preparing is O(text); build one per open book
/// and keep it, rather than paying that for every anchor.
nonisolated struct AnchoredText: Sendable {
    /// A match further than this fraction of the book from the reported percentage is refused:
    /// it is a coincidence, not the reader's place.
    static let maximumDrift = 0.15
    /// ...but never narrower than this many folded bytes (roughly 200 words), or a short text's
    /// window would be smaller than one sentence.
    static let minimumDriftBytes = 1_000
    /// A one-sided needle shorter than this (folded bytes) is too likely to recur.
    static let minimumPartialNeedle = 16

    let words: [Substring]
    let wordFirstTokens: [Int]
    let wordStarts: [Int]
    let folded: [UInt8]
    let tokenCount: Int

    init(_ text: String) {
        words = text.split(whereSeparator: \.isWhitespace)
        var firstTokens: [Int] = [], starts: [Int] = [], bytes: [UInt8] = []
        firstTokens.reserveCapacity(words.count)
        starts.reserveCapacity(words.count)
        var token = 0
        for word in words {
            firstTokens.append(token)
            starts.append(bytes.count)
            bytes.append(contentsOf: ReadingAnchor.fold(word).utf8)
            token += BookTokenizer.splitHyphens(word).count
        }
        wordFirstTokens = firstTokens
        wordStarts = starts
        folded = bytes
        tokenCount = token
    }

    // MARK: Building

    func anchor(atToken tokenIndex: Int) -> ReadingAnchor? {
        word(containingToken: tokenIndex).map { ReadingAnchor(words: words, at: $0) }
    }

    /// The source words around a position, for an offer to show where it would take the reader.
    func snippet(aroundToken tokenIndex: Int, radius: Int = 4) -> String {
        guard let w = word(containingToken: tokenIndex) else { return "" }
        let lower = max(0, w - radius), upper = min(words.count, w + radius + 1)
        return (lower > 0 ? "…" : "") + words[lower..<upper].joined(separator: " ")
            + (upper < words.count ? "…" : "")
    }

    /// The first token of the source word containing `tokenIndex`: where a resolved anchor lands.
    func wordStartToken(_ tokenIndex: Int) -> Int? {
        word(containingToken: tokenIndex).map { wordFirstTokens[$0] }
    }

    func word(containingToken tokenIndex: Int) -> Int? {
        guard tokenIndex >= 0, tokenIndex < tokenCount else { return nil }
        return lastIndex(in: wordFirstTokens, atOrBelow: tokenIndex)
    }

    // MARK: Resolving

    /// The token index `anchor` names, or nil when it cannot be placed with confidence — the
    /// caller then falls back to `fraction`.
    func resolve(_ anchor: ReadingAnchor, near fraction: Double) -> Int? {
        let core = ReadingAnchor.fold(anchor.text)
        guard !core.isEmpty, !folded.isEmpty else { return nil }
        let before = ReadingAnchor.fold(anchor.before), after = ReadingAnchor.fold(anchor.after)
        let needles: [(bytes: String, coreOffset: Int, partial: Bool)] = [
            (before + core + after, before.utf8.count, false),
            (before + core, before.utf8.count, true),
            (core + after, 0, true),
        ]
        let expected = Int(Double(folded.count) * min(max(fraction, 0), 1))
        let drift = max(Int(Double(folded.count) * Self.maximumDrift), Self.minimumDriftBytes)
        for needle in needles {
            if needle.partial, needle.bytes.utf8.count < Self.minimumPartialNeedle { continue }
            guard let nearest = occurrences(of: Array(needle.bytes.utf8))
                .map({ $0 + needle.coreOffset })
                .min(by: { abs($0 - expected) < abs($1 - expected) })
            else { continue }
            guard abs(nearest - expected) <= drift,
                  let w = lastIndex(in: wordStarts, atOrBelow: nearest) else { return nil }
            return wordFirstTokens[w]
        }
        return nil
    }

    func occurrences(of needle: [UInt8]) -> [Int] {
        guard !needle.isEmpty, needle.count <= folded.count else { return [] }
        var starts: [Int] = []
        folded.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { pattern in
                var from = 0
                while from + needle.count <= haystack.count,
                      let hit = memmem(haystack.baseAddress! + from, haystack.count - from,
                                       pattern.baseAddress!, needle.count) {
                    let start = haystack.baseAddress!.distance(to: hit)
                    starts.append(start)
                    from = start + 1
                }
            }
        }
        return starts
    }

    /// The last index whose value is ≤ `value` in an ascending array. Words that fold to nothing
    /// share their start with the next word, which wins because it comes later.
    func lastIndex(in ascending: [Int], atOrBelow value: Int) -> Int? {
        var low = 0, high = ascending.count
        while low < high {
            let mid = (low + high) / 2
            if ascending[mid] <= value { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
