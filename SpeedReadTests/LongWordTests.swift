import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("Long words")
struct LongWordTests {

    // MARK: - Which tokens are long, and what kind

    @Test(arguments: ["reading", "communication", "“Hello,”", "(understand)", "1952", "www.x.org"])
    func ordinaryTokensAreLeftAlone(word: String) {
        #expect(LongWord.kind(of: word) == .ordinary)
        #expect(LongWord.pieces(of: word) == [word])
    }

    @Test(arguments: ["electroencephalographically", "“Incomprehensibilities!”", "romantic—something—else"])
    func longWordsAreSplittable(word: String) {
        #expect(LongWord.kind(of: word) == .splittable)
    }

    @Test(arguments: ["www.gutenberg.org/ebooks/1952", "someone@example-mail.com", "ISBN978-3-16-148410-0",
                      "(https://example.org/a)"])
    func longNonWordsAreLiteral(word: String) {
        #expect(LongWord.kind(of: word) == .literal)
        // Mutation: split literals too. The operator asked for these to stay whole (2026-10-04).
        #expect(LongWord.pieces(of: word) == [word])
    }

    @Test func surroundingPunctuationDoesNotMakeAWordLong() {
        // Thirteen letters inside quotes and a comma: 16 characters, still one ordinary word.
        #expect(LongWord.kind(of: "“communication,”") == .ordinary)
        #expect(LongWord.kind(of: "“communications,”") == .splittable)
    }

    // MARK: - How a long word is split

    @Test(arguments: ["electroencephalographically", "Incomprehensibilities", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAH",
                      "“Supercalifragilisticexpialidocious!”", "romantic—something—else", "counterrevolutionaries",
                      // Greedy cuts would leave "AH" alone: 12 + 12 + 2.
                      "AAAAAAAAAAAAAAAAAAAAAAAAAH"])
    func piecesAreShortAndRebuildTheWord(word: String) throws {
        let pieces = LongWord.pieces(of: word)
        #expect(pieces.count >= 2)
        for piece in pieces {
            #expect(piece.count <= LongWord.maxPieceLength + 2, "\(piece) from \(word)")
            #expect(piece.count >= 3, "\(piece) from \(word)")
        }
        let rebuilt = pieces.dropLast().map { $0.hasSuffix("-") ? String($0.dropLast()) : $0 }.joined()
            + (pieces.last ?? "")
        #expect(rebuilt == word)
    }

    @Test func piecesAreBalancedRatherThanLeavingAStub() throws {
        let pieces = LongWord.pieces(of: "electroencephalographically")
        let lengths = pieces.map(\.count)
        // Greedy thirteen-letter cuts would leave "ly"; balanced cuts keep every piece readable.
        #expect(try #require(lengths.min()) >= 5)
    }

    @Test func aBreakAtADashAddsNoHyphen() {
        #expect(LongWord.pieces(of: "romantic—something—else") == ["romantic—", "something—", "else"])
    }

    @Test func aBreakInsideLettersIsMarkedWithAHyphen() throws {
        let pieces = LongWord.pieces(of: "electroencephalographically")
        for piece in pieces.dropLast() {
            #expect(piece.hasSuffix("-"))
        }
        #expect(try #require(pieces.last).hasSuffix("-") == false)
    }

    @Test func leadingAndTrailingPunctuationStayWithTheirEnds() throws {
        let pieces = LongWord.pieces(of: "“Incomprehensibilities!”")
        #expect(try #require(pieces.first).hasPrefix("“"))
        #expect(try #require(pieces.last).hasSuffix("!”"))
    }

    @Test func aRunOfLettersLongerThanAnyWordIsShownWholeAndCostsLinearTime() {
        // Mutation: drop the length bound. Splitting is then quadratic, on the main actor, for a
        // token any broken or hostile file can contain.
        let junk = String(repeating: "a", count: 200_000)
        let start = Date()
        #expect(LongWord.kind(of: junk) == .literal)
        #expect(LongWord.pieces(of: junk) == [junk])
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(LongWord.kind(of: String(repeating: "a", count: LongWord.maxSplittableLength)) == .splittable)
    }
}
