import Foundation
import Testing
@testable import SpeedRead

/// A reading anchor is how a position survives two different tokenizers: the server and every
/// other reader address the book by its own words, SpeedRead by its token index. These tests
/// hold the two directions to each other on real text, not only on strings written for them.
@Suite("Reading anchor")
@MainActor
struct ReadingAnchorTests {
    // MARK: Building

    @Test func theAnchorTextIsTheWholeSourceWordEvenFromAHyphenSplitToken() {
        let text = "one two self-awareness three"
        // Tokens: one, two, self-, awareness, three.
        #expect(ReadingAnchor.build(text: text, tokenIndex: 3)
            == ReadingAnchor(text: "self-awareness", before: "one two", after: "three"))
        #expect(ReadingAnchor.build(text: text, tokenIndex: 2)?.text == "self-awareness")
    }

    @Test func contextIsEightWordsEachSideClippedAtTheEdges() throws {
        let words = (0..<30).map { "w\($0)" }
        let text = words.joined(separator: "\n ")

        let middle = try #require(ReadingAnchor.build(text: text, tokenIndex: 15))
        #expect(middle.before == words[7..<15].joined(separator: " "))
        #expect(middle.after == words[16..<24].joined(separator: " "))
        #expect(ReadingAnchor.build(text: text, tokenIndex: 0)?.before == "")
        #expect(ReadingAnchor.build(text: text, tokenIndex: 29)?.after == "")
        #expect(ReadingAnchor.build(text: text, tokenIndex: 30) == nil)
        #expect(ReadingAnchor.build(text: "", tokenIndex: 0) == nil)
    }

    @Test func anAnchorIsTrimmedToWhatTheServerAccepts() throws {
        let long = String(repeating: "x", count: 100)
        let context = Array(repeating: long, count: 8).joined(separator: " ")
        let anchor = try #require(ReadingAnchor(text: "word", before: context, after: context).wireSafe())
        // 8 words of 100 scalars plus spaces is 807; whole words come off the far end.
        #expect(anchor.before == Array(repeating: long, count: 5).joined(separator: " "))
        #expect(anchor.after == anchor.before)
        #expect(anchor.before.unicodeScalars.count <= ReadingAnchor.maximumContextScalars)
        #expect(ReadingAnchor(text: "near", before: "a b", after: "c").wireSafe()
            == ReadingAnchor(text: "near", before: "a b", after: "c"))
    }

    @Test func anAnchorTheServerWouldRejectIsNotSent() {
        #expect(ReadingAnchor(text: String(repeating: "y", count: 201), before: "", after: "").wireSafe() == nil)
        #expect(ReadingAnchor(text: String(repeating: "y", count: 200), before: "", after: "").wireSafe() != nil)
        #expect(ReadingAnchor(text: "\u{AD}\u{200B}", before: "a", after: "b").wireSafe() == nil)
    }

    @Test func nullContextDecodesAsEmpty() throws {
        let anchor = try JSONDecoder().decode(ReadingAnchor.self, from: Data(#"{"text":"Gregor","before":null}"#.utf8))
        #expect(anchor == ReadingAnchor(text: "Gregor", before: "", after: ""))
    }

    @Test func aTrailingHyphenWordStaysItsOwnWord() {
        // "pre-" is a whole source word; joining it to the next token would invent "pre-and".
        let anchor = ReadingAnchor.build(text: "pre- and post-war", tokenIndex: 0)
        #expect(anchor?.text == "pre-")
        #expect(anchor?.after == "and post-war")
    }

    // MARK: Resolving

    @Test func foldingIgnoresCaseWhitespaceDashAndQuoteVariants() {
        let text = "The clerk said “Gregor—come here” and left."
        let anchor = ReadingAnchor(text: "here\"", before: "said \"GREGOR-COME", after: "and left.")
        // Tokens: The clerk said “Gregor—come here” and left. — the em-dash does not split, so
        // "here”" is token 4.
        #expect(anchor.resolve(in: text, near: 0.5) == 4)
    }

    /// The server's FOLD_VECTORS, verbatim, escapes included (CWNG fold v2, 2026-10-03). Both
    /// sides pin this same list; none of it was produced by the code under test.
    @Test("fold matches the server", arguments: [
        ("Caf\u{E9}", "cafe"),
        ("Cafe\u{301}", "cafe"),
        ("CAF\u{C9}", "cafe"),
        ("glow\u{AD}ering", "glowering"),
        ("zero\u{200B}width", "zerowidth"),
        ("\u{201C}Gregor!\u{201D}", "\"gregor!\""),
        ("it\u{2019}s", "it's"),
        ("self\u{2014}aware", "self-aware"),
        ("a\u{A0}b c\n\td", "abcd"),
        ("\u{FB01}ne", "fine"),
        ("Stra\u{DF}e", "stra\u{DF}e"),
        ("\u{C6}SIR", "\u{E6}sir"),
        ("zero\u{200B}width\u{FEFF}", "zerowidth"),
        ("\u{201C}Gregor\u{2014}come here!\u{201D}", "\"gregor-comehere!\""),
        ("it\u{2019}s \u{2018}so\u{2019}", "it's'so'"),
        ("\u{FB01}ne\u{A0}\u{2163}", "fineiv"),
        ("\u{2032}", "\u{2032}"),
    ])
    func foldMatchesTheServer(input: String, expected: String) {
        #expect(ReadingAnchor.fold(input) == expected)
    }

    @Test func aMissReturnsNilSoTheCallerFallsBackToThePercentage() {
        let anchor = ReadingAnchor(text: "absent", before: "nothing here", after: "matches this")
        #expect(anchor.resolve(in: "a completely different book about other things", near: 0.3) == nil)
    }

    @Test func aRepeatedPassageResolvesToTheCopyNearestThePercentage() {
        let passage = "the bell rang twice and nobody came"
        let text = ([passage] + Array(repeating: "filler", count: 200) + [passage]).joined(separator: " ")
        let anchor = ReadingAnchor(text: "twice", before: "the bell rang", after: "and nobody came")
        let tokens = Book.tokenize(text)

        let early = anchor.resolve(in: text, near: 0.02)
        let late = anchor.resolve(in: text, near: 0.98)

        #expect(early.map { tokens[$0] } == "twice")
        #expect(late.map { tokens[$0] } == "twice")
        #expect(early == 3)
        #expect(late == tokens.count - 4)
    }

    @Test func aMatchFarFromThePercentageIsRefused() {
        // One copy, but at the other end of the book from where the server says the reader is:
        // trusting it would move the reader across the whole book on a coincidence.
        let text = (["the bell rang twice and nobody came"] + Array(repeating: "filler", count: 400))
            .joined(separator: " ")
        let anchor = ReadingAnchor(text: "twice", before: "bell rang", after: "and nobody")
        #expect(anchor.resolve(in: text, near: 0.95) == nil)
        #expect(anchor.resolve(in: text, near: 0.05) == 3)
    }

    // MARK: Real text

    /// The server's own example, captured from its fixture of this book at Kindle page 60.
    @Test func theServersMetamorphosisAnchorLandsOnTheSameSentence() throws {
        let text = try sampleText("TheMetamorphosis")
        let tokens = Book.tokenize(text)
        let anchor = ReadingAnchor(
            text: "his",
            before: "up everything and stayed there immobile. “Gregor!” shouted",
            after: "sister, glowering at him and shaking her fist."
        )

        let index = try #require(anchor.resolve(in: text, near: 0.60))

        #expect(tokens[index] == "his")
        #expect(tokens[index - 1] == "shouted")
        #expect(tokens[index + 1] == "sister,")
    }

    @Test(arguments: ["TheMetamorphosis", "TheYellowWallpaper"])
    func everyPositionRoundTripsThroughItsAnchor(book: String) throws {
        let text = try sampleText(book)
        let prepared = AnchoredText(text)
        let count = Book.tokenize(text).count
        #expect(prepared.tokenCount == count)
        var misses: [Int] = []
        for index in stride(from: 0, to: count, by: 37) {
            let anchor = try #require(prepared.anchor(atToken: index))
            let resolved = prepared.resolve(anchor, near: Double(index) / Double(count))
            // A hyphen-split word resolves to its first token: that is the whole word's start.
            if resolved != prepared.wordStartToken(index) { misses.append(index) }
            // The cheap single-position builder must agree with the prepared one.
            if index % (37 * 20) == 0 { #expect(ReadingAnchor.build(text: text, tokenIndex: index) == anchor) }
        }
        #expect(misses.isEmpty, "unresolved or misplaced positions: \(misses.prefix(10))")
    }

    private func sampleText(_ name: String) throws -> String {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        return try EPUBExtractor().extractText(from: Data(contentsOf: url)).text
    }
}
