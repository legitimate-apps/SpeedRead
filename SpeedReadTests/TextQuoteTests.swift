import Foundation
import Testing
@testable import SpeedRead

/// A text quote is how a highlight or bookmark survives two different copies of a book: this
/// device addresses it by token range, the library server and every other reader by the words.
/// These tests hold the two directions to each other.
@Suite("Text quote")
struct TextQuoteTests {
    private static let words = (0..<300).map { "w\($0)" }
    private static let text = AnchoredText(words.joined(separator: " "))

    // MARK: Building

    @Test func aQuoteIsTheSourceWordsOfTheRangeWithEightWordsEachSide() throws {
        let quote = try #require(Self.text.quote(fromToken: 100, toToken: 102))
        #expect(quote == TextQuote(exact: "w100 w101 w102",
                                   prefix: Self.words[92..<100].joined(separator: " "),
                                   suffix: Self.words[103..<111].joined(separator: " ")))
    }

    @Test func aRangeThatSplitsAHyphenatedWordQuotesTheWholeWord() throws {
        // Tokens: one, two, self-, awareness, three, four.
        let text = AnchoredText("one two self-awareness three four")
        let quote = try #require(text.quote(fromToken: 3, toToken: 4))
        #expect(quote == TextQuote(exact: "self-awareness three", prefix: "one two", suffix: "four"))
    }

    @Test func aRangeOutsideTheBookHasNoQuote() {
        #expect(Self.text.quote(fromToken: 299, toToken: 300) == nil)
        #expect(Self.text.quote(fromToken: -1, toToken: 3) == nil)
        #expect(Self.text.quote(fromToken: 5, toToken: 4) == nil)
        #expect(AnchoredText("").quote(fromToken: 0, toToken: 0) == nil)
    }

    @Test func aQuoteIsTrimmedToWhatTheServerAccepts() throws {
        let long = String(repeating: "x", count: 100)
        let context = Array(repeating: long, count: 8).joined(separator: " ")
        let quote = try #require(TextQuote(exact: "word", prefix: context, suffix: context).wireSafe())
        #expect(quote.prefix == Array(repeating: long, count: 5).joined(separator: " "))
        #expect(quote.suffix == quote.prefix)

        let tooLong = TextQuote(exact: String(repeating: "y", count: TextQuote.maximumExactScalars + 1),
                                prefix: "", suffix: "")
        #expect(tooLong.wireSafe() == nil)
        #expect(TextQuote(exact: " \u{200B} ", prefix: "a", suffix: "b").wireSafe() == nil)
    }

    // MARK: Resolving

    @Test func aQuoteResolvesBackToTheSameTokens() throws {
        for (start, end) in [(0, 0), (0, 4), (150, 160), (299, 299), (290, 299)] {
            let quote = try #require(Self.text.quote(fromToken: start, toToken: end))
            #expect(Self.text.resolve(quote, near: nil) == start...end)
        }
    }

    @Test func aQuoteResolvesAcrossADifferentCopyOfTheBook() throws {
        // The library's copy: other spacing and line breaks, curly quotes and accents.
        let mine = AnchoredText("He said \"cafe\" was well-known, and left the room. Later that night")
        let quote = TextQuote(exact: "“Café” was well-known,", prefix: "He  said", suffix: "and\nleft")
        // Tokens: He, said, "cafe", was, well-, known,, and ...
        #expect(mine.resolve(quote, near: nil) == 2...5)
    }

    @Test func anAmbiguousQuoteIsRefusedUnlessAPercentagePlacesIt() throws {
        let repeated = AnchoredText(Array(repeating: "the same refrain again and again", count: 40)
            .joined(separator: " filler words between each refrain "))
        let quote = TextQuote(exact: "same refrain", prefix: "", suffix: "")
        #expect(repeated.resolve(quote, near: nil) == nil)

        let placed = try #require(repeated.resolve(quote, near: 0.5))
        let tokens = repeated.tokenCount
        #expect(abs(Double(placed.lowerBound) / Double(tokens) - 0.5) < 0.03)
        #expect(placed.count == 2)
    }

    @Test func contextBreaksATieThatTheExactWordsAloneCannot() throws {
        let text = AnchoredText("alpha beta gamma delta. epsilon zeta gamma delta. eta theta")
        let second = TextQuote(exact: "gamma delta.", prefix: "epsilon zeta", suffix: "eta theta")
        // Tokens: alpha0 beta1 gamma2 delta.3 epsilon4 zeta5 gamma6 delta.7 eta8 theta9
        #expect(text.resolve(second, near: nil) == 6...7)
    }

    @Test func contextThatNoLongerMatchesFallsBackToOneSide() throws {
        let text = AnchoredText((0..<40).map { "word\($0)" }.joined(separator: " "))
        let quote = TextQuote(exact: "word20 word21", prefix: "word18 word19", suffix: "an edited sentence")
        #expect(text.resolve(quote, near: nil) == 20...21)
    }

    @Test func aBookmarkWithNoExactWordsIsPlacedBetweenItsContext() throws {
        let quote = TextQuote(exact: "", prefix: "w40 w41 w42 w43", suffix: "w44 w45 w46 w47")
        #expect(Self.text.resolve(quote, near: nil) == 44...44)
    }

    @Test func wordsTheBookDoesNotContainResolveToNothing() {
        #expect(Self.text.resolve(TextQuote(exact: "nowhere in it", prefix: "", suffix: ""), near: nil) == nil)
        #expect(Self.text.resolve(TextQuote(exact: "", prefix: "", suffix: ""), near: nil) == nil)
    }
}
