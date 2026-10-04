import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("Bounded passages")
struct TextEnclosuresTests {

    // MARK: - Quotes

    @Test(arguments: ["He said “I am here now” and left.", "He said \"I am here now\" and left."])
    func aQuoteBoundsTheWordsInsideIt(text: String) {
        let found = TextEnclosures.scan(text)
        #expect(marks(found, at: 1) == [])
        #expect(marks(found, at: 2) == ["“”"])
        #expect(marks(found, at: 4) == ["“”"])
        #expect(marks(found, at: 5) == ["“”"])
        #expect(marks(found, at: 6) == [])
    }

    @Test func aQuoteContinuedAtEachParagraphRunsUntilItCloses() {
        let text = "Before.\n\n“First paragraph opens.\n\n“Second carries on.\n\n“Third ends here.” After."
        let found = TextEnclosures.scan(text)
        #expect(marks(found, at: 0) == [])
        for index in 1...9 {
            #expect(marks(found, at: index) == ["“”"], "word \(index)")
        }
        #expect(marks(found, at: 10) == [])
    }

    @Test func aQuoteLeftOpenAtAParagraphEndThatIsNotContinuedIsNotABound() {
        // Mutation: carry every open quote across paragraphs. A stray quote mark would then put
        // the rest of the book "inside quotes".
        let text = "“Open and never closed.\n\nNext paragraph, “then a real one” here."
        let found = TextEnclosures.scan(text)
        #expect(marks(found, at: 1) == [])
        #expect(marks(found, at: 5) == [])
        #expect(marks(found, at: 7) == ["“”"])
    }

    @Test func aStrayOpeningQuoteCannotPairWithAClosingMarkParagraphsLater() {
        let text = "“Open and never closed.\n\nNext paragraph here.” And more."
        let found = TextEnclosures.scan(text)
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [], "word \(index)")
        }
    }

    @Test func apostrophesAreNotQuotes() {
        let found = TextEnclosures.scan("the dogs’ bowls and ’tis rock ’n’ roll, 'em all")
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [])
        }
    }

    @Test func singleQuotedDialogueIsABound() {
        let found = TextEnclosures.scan("‘Come here now,’ she said.")
        #expect(marks(found, at: 1) == ["‘’"])
        #expect(marks(found, at: 3) == [])
    }

    @Test func aStrayClosingQuoteChangesNothing() {
        let found = TextEnclosures.scan("he said” then left")
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [])
        }
    }

    // MARK: - Stars, brackets, dashes

    @Test func standaloneStarsBoundTheirPassageAndAreSilent() {
        let found = TextEnclosures.scan("*** START OF THE EBOOK ***\n\nText.")
        #expect(marks(found, at: 1) == ["******"])
        #expect(marks(found, at: 4) == ["******"])
        #expect(marks(found, at: 6) == [])
        #expect(found.isSilent(0) && found.isSilent(5))
        #expect(!found.isSilent(1) && !found.isSilent(6))
    }

    @Test func aSceneBreakOfStarsBoundsNothingAndStaysVisible() {
        let found = TextEnclosures.scan("End of scene.\n\n* * *\n\nNext scene.")
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [])
            #expect(!found.isSilent(index))
        }
    }

    @Test func underscoresAndStarsAroundWordsAreBounds() {
        let found = TextEnclosures.scan("a _very_ good *bold claim* here")
        #expect(marks(found, at: 1) == ["__"])
        #expect(marks(found, at: 2) == [])
        #expect(marks(found, at: 3) == ["**"])
        #expect(marks(found, at: 4) == ["**"])
        #expect(marks(found, at: 5) == [])
    }

    @Test func parenthesesNestInsideQuotesOutermostFirst() {
        let found = TextEnclosures.scan("“Read (this part) now” he said")
        #expect(marks(found, at: 0) == ["“”"])
        #expect(marks(found, at: 1) == ["“”", "()"])
        #expect(marks(found, at: 2) == ["“”", "()"])
        #expect(marks(found, at: 3) == ["“”"])
        #expect(marks(found, at: 4) == [])
    }

    @Test(arguments: ["John is a physician—perhaps that is one reason—I do not get well.",
                      "John is a physician--perhaps that is one reason--I do not get well.",
                      "John is a physician — perhaps that is one reason — I do not get well."])
    func aPairOfDashesInOneSentenceBoundsAnAside(text: String) throws {
        let found = TextEnclosures.scan(text)
        let words = BookTokenizer.tokenize(text)
        let inside = try #require(words.firstIndex { $0.hasPrefix("that") })
        let after = try #require(words.firstIndex { $0 == "do" })
        #expect(marks(found, at: inside) == ["——"])
        #expect(marks(found, at: after) == [])
        #expect(marks(found, at: 0) == [])
    }

    @Test(arguments: ["the height of romantic felicity—but that would be asking too much of fate!",
                      "A dash—here. Another dash—there."])
    func aLoneDashOrDashesInDifferentSentencesBoundNothing(text: String) {
        let found = TextEnclosures.scan(text)
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [])
        }
    }

    @Test func anInlineBoundCannotRunAbusivelyLong() {
        // Mutation: lift the cap. An unbalanced parenthesis would then swallow a whole chapter.
        let long = "(" + Array(repeating: "word", count: 200).joined(separator: " ") + ")"
        #expect(marks(TextEnclosures.scan(long), at: 100) == [])
        let short = "(" + Array(repeating: "word", count: 20).joined(separator: " ") + ")"
        #expect(marks(TextEnclosures.scan(short), at: 10) == ["()"])
    }

    @Test func anInlineBoundEndsAtItsParagraph() {
        let found = TextEnclosures.scan("an (open aside\n\nnew paragraph) here")
        for index in 0..<found.tokenCount {
            #expect(marks(found, at: index) == [])
        }
    }

    // MARK: - Alignment with the book's words

    @Test func itCountsExactlyTheWordsTheBookHas() {
        let text = "“Well-known,” he said—\r\n\r\nself-evident (truly)--yes *** x ***\n_a_ ‘b’ end."
        #expect(TextEnclosures.scan(text).tokenCount == BookTokenizer.tokenize(text).count)
        #expect(TextEnclosures.empty.tokenCount == 0)
        #expect(TextEnclosures.empty.enclosures(at: 0).isEmpty)
    }

    @Test func aWholeNovelScansQuickly() {
        let paragraph = "“I am here,” she said—quietly—and (as ever) *nobody* answered. It was late.\n\n"
        let text = String(repeating: paragraph, count: 8_000)
        let start = Date()
        let found = TextEnclosures.scan(text)
        let elapsed = Date().timeIntervalSince(start)
        #expect(found.tokenCount == 8_000 * 12)
        #expect(elapsed < 5, "112k words took \(elapsed)s")
        print("TextEnclosures.scan: \(found.tokenCount) words in \(elapsed)s")
    }

    private func marks(_ found: TextEnclosures, at index: Int) -> [String] {
        found.enclosures(at: index).map { $0.opener + $0.closer }
    }
}
