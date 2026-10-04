//  TextEnclosures.swift
import Foundation

/// A passage the author bounded with punctuation: a quotation, an aside in parentheses or between
/// dashes, a run of words between stars or underscores. RSVP shows only one word, so the marks
/// that open and close the passage are drawn faintly above every word inside it.
nonisolated struct TextEnclosure: Equatable, Sendable {
    /// The marks as drawn, which for quotes are always the curly pair whatever the source used.
    let opener: String
    let closer: String
    /// The book's word indices inside the marks.
    let range: ClosedRange<Int>
}

/// Every bounded passage in a book, found in one pass over its text.
///
/// The scan is a stack of open marks, not a model or a regular expression: the conventions are
/// typographic rules, so a deterministic pass gets them right, gives the phone and the watch the
/// same answer for the same word, and costs a fraction of a second for a novel on either device.
/// It errs towards showing nothing: a mark that never closes bounds nothing, an inline bound
/// cannot leave its paragraph or run past a cap, and dashes pair only within one sentence. Only
/// quotations cross paragraphs, and only by the convention that a quotation continuing into the
/// next paragraph reopens it there.
nonisolated struct TextEnclosures: Sendable {
    static let empty = TextEnclosures(tokenCount: 0, ranges: [], silent: [])

    /// How many words the scan saw, which must equal the book's word count for the result to be
    /// used: the same `BookTokenizer` rules decide both.
    let tokenCount: Int
    /// Sorted by start, an outer passage before an inner one that starts on the same word.
    private let ranges: [TextEnclosure]
    private let parents: [Int?]
    private let silent: Set<Int>

    init(tokenCount: Int, ranges: [TextEnclosure], silent: Set<Int>) {
        self.tokenCount = tokenCount
        self.silent = silent
        let sorted = ranges.sorted {
            $0.range.lowerBound == $1.range.lowerBound
                ? $0.range.upperBound > $1.range.upperBound
                : $0.range.lowerBound < $1.range.lowerBound
        }
        // Keep only properly nested passages, so the lookup's ancestor walk is exact.
        var kept: [TextEnclosure] = []
        var parents: [Int?] = []
        var open: [Int] = []
        for enclosure in sorted {
            while let top = open.last, kept[top].range.upperBound < enclosure.range.lowerBound {
                open.removeLast()
            }
            if let top = open.last, kept[top].range.upperBound < enclosure.range.upperBound { continue }
            parents.append(open.last)
            kept.append(enclosure)
            open.append(kept.count - 1)
        }
        self.ranges = kept
        self.parents = parents
    }

    /// The passages around a word, outermost first.
    func enclosures(at index: Int) -> [TextEnclosure] {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].range.lowerBound <= index { low = mid + 1 } else { high = mid }
        }
        var found: [TextEnclosure] = []
        var candidate = low > 0 ? low - 1 : nil
        while let current = candidate {
            if ranges[current].range.contains(index) { found.append(ranges[current]) }
            candidate = parents[current]
        }
        return found.reversed()
    }

    /// A word that is only the mark opening or closing a passage, such as a lone `***`. The marks
    /// above the passage already show it, so playback does not spend a beat on it.
    func isSilent(_ index: Int) -> Bool {
        silent.contains(index)
    }

    static func scan(_ text: String) -> TextEnclosures {
        var scanner = EnclosureScanner()
        var index = 0
        var newlines = 0
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let character = text[cursor]
            if character.isWhitespace {
                if character.isNewline { newlines += 1 }
                cursor = text.index(after: cursor)
                continue
            }
            let start = cursor
            while cursor < text.endIndex, !text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            let tokens = BookTokenizer.splitHyphens(text[start..<cursor])
            let lineBreak: EnclosureScanner.Break = index == 0 || newlines >= 2 ? .paragraph
                : newlines == 1 ? .line : .none
            for (offset, token) in tokens.enumerated() {
                // "a--b" splits into "a-" and "-b": the pair is one dash after "a".
                var normalized = token.replacingOccurrences(of: "--", with: "\u{2014}")
                if offset + 1 < tokens.count, normalized.hasSuffix("-"), tokens[offset + 1].hasPrefix("-") {
                    normalized = String(normalized.dropLast()) + "\u{2014}"
                }
                if offset > 0, normalized.hasPrefix("-"), tokens[offset - 1].hasSuffix("-") {
                    normalized.removeFirst()
                }
                scanner.consume(normalized, at: index, after: offset == 0 ? lineBreak : .none)
                index += 1
            }
            newlines = 0
        }
        return TextEnclosures(tokenCount: index, ranges: scanner.ranges, silent: scanner.silent)
    }
}

/// The stack machine behind `TextEnclosures.scan`, fed one word at a time.
nonisolated private struct EnclosureScanner {
    enum Break { case none, line, paragraph }

    enum Kind: Equatable {
        case doubleQuote
        case singleQuote
        case marker(String)
        case bracket(Character)
        case dash

        var marks: (String, String) {
            switch self {
            case .doubleQuote: ("\u{201C}", "\u{201D}")
            case .singleQuote: ("\u{2018}", "\u{2019}")
            case .marker(let run): (run, run)
            case .bracket(let open): (String(open), String(Self.closing[open] ?? open))
            case .dash: ("\u{2014}", "\u{2014}")
            }
        }

        /// The longest a passage of this kind may run, in words. Quotations are bounded by their
        /// paragraphs instead; an aside or an emphasis that runs on is a stray mark.
        var cap: Int {
            switch self {
            case .doubleQuote, .singleQuote: 600
            case .marker: 60
            case .bracket: 80
            case .dash: 30
            }
        }

        static let closing: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    }

    struct Open {
        let kind: Kind
        let start: Int
        /// The word that is only this mark, when it stands alone.
        let markWord: Int?
        /// Where the cap is counted from: the start, or the paragraph that last reopened a quotation.
        var anchor: Int
    }

    private(set) var ranges: [TextEnclosure] = []
    private(set) var silent: Set<Int> = []
    private var stack: [Open] = []

    mutating func consume(_ token: String, at index: Int, after lineBreak: Break) {
        var characters = Array(token)
        if lineBreak == .paragraph {
            let continued = continueQuotes(leading: characters, at: index)
            characters.removeFirst(continued)
        }
        guard let first = characters.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = characters.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            standalone(characters, at: index)
            return
        }
        leading(characters[..<first], at: index, lineStart: lineBreak != .none)
        for character in characters[first...last] where character == "\u{2014}" {
            if isOpen(.dash) { close(.dash, end: index) } else { open(.dash, start: index) }
        }
        trailing(characters[(last + 1)...], at: index)
    }

    // MARK: - Where a mark sits in its word

    private mutating func leading(_ marks: ArraySlice<Character>, at index: Int, lineStart: Bool) {
        for run in runs(marks) {
            switch run.first {
            case "\u{201C}", "\"": openQuote(at: index, lineStart: lineStart)
            case "\u{2018}", "'": open(.singleQuote, start: index)
            case "(", "[", "{": open(.bracket(run.first!), start: index)
            case "*", "_": open(.marker(String(run)), start: index)
            case "\u{2014}": if isOpen(.dash) { close(.dash, end: index - 1) } else { open(.dash, start: index) }
            default: break
            }
        }
    }

    private mutating func trailing(_ marks: ArraySlice<Character>, at index: Int) {
        for run in runs(marks) {
            switch run.first {
            case "\u{201D}", "\"": close(.doubleQuote, end: index)
            case "\u{2019}", "'": if isOpen(.singleQuote) { close(.singleQuote, end: index) }
            case ")", "]", "}": closeBracket(run.first!, end: index)
            case "*", "_": close(.marker(String(run)), end: index)
            case "\u{2014}": if isOpen(.dash) { close(.dash, end: index) } else { open(.dash, start: index + 1) }
            case ".", "?", "!": dropAll(.dash)
            default: break
            }
        }
    }

    /// A word with no letters or digits: a lone mark, which bounds the words beside it.
    private mutating func standalone(_ marks: [Character], at index: Int) {
        guard let mark = marks.first, marks.allSatisfy({ $0 == mark }) || mark == "\u{2014}" else { return }
        switch mark {
        case "*", "_":
            let kind = Kind.marker(String(marks))
            if isOpen(kind) { close(kind, end: index - 1, markWord: index) } else { open(kind, start: index + 1, markWord: index) }
        case "\u{2014}", "\u{2013}":
            if isOpen(.dash) { close(.dash, end: index - 1, markWord: index) } else { open(.dash, start: index + 1, markWord: index) }
        case "\u{201C}": open(.doubleQuote, start: index + 1, markWord: index)
        case "\u{201D}": close(.doubleQuote, end: index - 1, markWord: index)
        case "\"":
            if isOpen(.doubleQuote) { close(.doubleQuote, end: index - 1, markWord: index) }
            else { open(.doubleQuote, start: index + 1, markWord: index) }
        case "(", "[", "{": open(.bracket(mark), start: index + 1, markWord: index)
        case ")", "]", "}": closeBracket(mark, end: index - 1, markWord: index)
        default: break
        }
    }

    // MARK: - The stack

    private func isOpen(_ kind: Kind) -> Bool {
        stack.contains { $0.kind == kind }
    }

    private mutating func open(_ kind: Kind, start: Int, markWord: Int? = nil) {
        stack.append(Open(kind: kind, start: start, markWord: markWord, anchor: start))
    }

    /// Double quotes do not nest in English, so a second opening mark means the first was never
    /// closed, unless it starts a line, where it continues the quotation (some books keep a
    /// paragraph per line rather than a blank line between paragraphs).
    private mutating func openQuote(at index: Int, lineStart: Bool) {
        if let existing = stack.lastIndex(where: { $0.kind == .doubleQuote }) {
            if lineStart { return }
            stack.removeSubrange(existing...)
        }
        open(.doubleQuote, start: index)
    }

    private mutating func close(_ kind: Kind, end: Int, markWord: Int? = nil) {
        guard let position = stack.lastIndex(where: { $0.kind == kind }) else { return }
        let opened = stack[position]
        stack.removeSubrange(position...)
        guard opened.start <= end, end - opened.anchor < kind.cap else { return }
        let (opener, closer) = kind.marks
        ranges.append(TextEnclosure(opener: opener, closer: closer, range: opened.start...end))
        if let word = opened.markWord { silent.insert(word) }
        if let markWord { silent.insert(markWord) }
    }

    private mutating func closeBracket(_ mark: Character, end: Int, markWord: Int? = nil) {
        guard let open = Kind.closing.first(where: { $0.value == mark })?.key else { return }
        close(.bracket(open), end: end, markWord: markWord)
    }

    private mutating func dropAll(_ kind: Kind) {
        if let position = stack.firstIndex(where: { $0.kind == kind }) {
            stack.removeSubrange(position...)
        }
    }

    /// At a paragraph start, inline marks end, and each open quotation survives only if the new
    /// paragraph reopens it. Returns how many leading marks were consumed as continuations.
    private mutating func continueQuotes(leading characters: [Character], at index: Int) -> Int {
        stack.removeAll { if case .doubleQuote = $0.kind { false } else if case .singleQuote = $0.kind { false } else { true } }
        var consumed = 0
        for (position, open) in stack.enumerated() {
            let mark = consumed < characters.count ? characters[consumed] : nil
            let continues = switch open.kind {
            case .doubleQuote: mark == "\u{201C}" || mark == "\""
            default: mark == "\u{2018}" || mark == "'"
            }
            guard continues else {
                stack.removeSubrange(position...)
                break
            }
            stack[position].anchor = index
            consumed += 1
        }
        return consumed
    }

    /// Splits marks into runs: a run of stars or underscores is one mark, anything else is one each.
    private func runs(_ marks: ArraySlice<Character>) -> [ArraySlice<Character>] {
        var runs: [ArraySlice<Character>] = []
        var start = marks.startIndex
        while start < marks.endIndex {
            var end = marks.index(after: start)
            if marks[start] == "*" || marks[start] == "_" {
                while end < marks.endIndex, marks[end] == marks[start] { end = marks.index(after: end) }
            }
            runs.append(marks[start..<end])
            start = end
        }
        return runs
    }
}
