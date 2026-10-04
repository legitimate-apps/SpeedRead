import Testing
@testable import SpeedRead

@Suite("ORP Calculator Tests")
struct ORPCalculatorTests {

    // MARK: - Basic word length buckets

    @Test func singleCharacterWord() {
        #expect(ORPCalculator.orpIndex(for: "I") == 0)
        #expect(ORPCalculator.orpIndex(for: "a") == 0)
    }

    @Test func twoToFiveCharacterWords() {
        #expect(ORPCalculator.orpIndex(for: "is") == 1)
        #expect(ORPCalculator.orpIndex(for: "the") == 1)
        #expect(ORPCalculator.orpIndex(for: "four") == 1)
        #expect(ORPCalculator.orpIndex(for: "hello") == 1)
    }

    @Test func sixToNineCharacterWords() {
        #expect(ORPCalculator.orpIndex(for: "reading") == 2)
        #expect(ORPCalculator.orpIndex(for: "absolute") == 2)
        #expect(ORPCalculator.orpIndex(for: "recognize") == 2)
    }

    @Test func tenToThirteenCharacterWords() {
        #expect(ORPCalculator.orpIndex(for: "understand") == 3)
        #expect(ORPCalculator.orpIndex(for: "presentation") == 3)
        #expect(ORPCalculator.orpIndex(for: "communication") == 3)
    }

    @Test func fourteenPlusCharacterWords() {
        #expect(ORPCalculator.orpIndex(for: "representations") == 4)
        #expect(ORPCalculator.orpIndex(for: "acknowledgements") == 4)
    }

    // MARK: - Leading punctuation handling

    @Test func leadingQuote() {
        #expect(ORPCalculator.orpIndex(for: "\"Hello\"") == 2)
    }

    @Test func leadingParenthesis() {
        #expect(ORPCalculator.orpIndex(for: "(test)") == 2)
    }

    @Test func leadingSingleQuote() {
        #expect(ORPCalculator.orpIndex(for: "'word") == 2)
    }

    // MARK: - Edge cases

    @Test func emptyString() {
        #expect(ORPCalculator.orpIndex(for: "") == 0)
    }

    @Test func punctuationOnly() {
        #expect(ORPCalculator.orpIndex(for: "...") == 0)
    }

    @Test func wordWithTrailingPunctuation() {
        #expect(ORPCalculator.orpIndex(for: "world.") == 1)
    }

    @Test func numberWord() {
        #expect(ORPCalculator.orpIndex(for: "42") == 1)
        #expect(ORPCalculator.orpIndex(for: "12345") == 1)
    }

    // MARK: - Word segments for display

    @Test func segmentsForSimpleWord() {
        let segments = ORPCalculator.segments(for: "reading")
        #expect(segments.before == "re")
        #expect(segments.focus == "a")
        #expect(segments.after == "ding")
    }

    @Test func segmentsForShortWord() {
        let segments = ORPCalculator.segments(for: "Hi")
        #expect(segments.before == "H")
        #expect(segments.focus == "i")
        #expect(segments.after == "")
    }

    @Test func segmentsForSingleChar() {
        let segments = ORPCalculator.segments(for: "I")
        #expect(segments.before == "")
        #expect(segments.focus == "I")
        #expect(segments.after == "")
    }

    @Test func segmentsForWordWithLeadingPunct() {
        let segments = ORPCalculator.segments(for: "\"Hello\"")
        #expect(segments.before == "\"H")
        #expect(segments.focus == "e")
        #expect(segments.after == "llo\"")
    }

    @Test func adversarialWordsKeepORPInBoundsAndSegmentsRoundTrip() {
        let words = [
            "",
            "x",
            "...?!—",
            "((\"Hello",
            "don't",
            "mother-in-law",
            "1234567890",
            String(repeating: "a", count: 1_024),
            "e\u{301}clair",
            "👩🏽‍🚀reading"
        ]

        for word in words {
            let index = ORPCalculator.orpIndex(for: word)
            let segments = ORPCalculator.segments(for: word)

            if word.isEmpty {
                #expect(index == 0)
                #expect(segments.focus.isEmpty)
            } else {
                #expect(index < word.count)
                #expect(segments.focus.count == 1)
            }
            #expect(segments.before + segments.focus + segments.after == word)
        }
    }

    // MARK: - Long non-words

    @Test func aLongNonWordPivotsOnItsMiddleSoItSitsCentered() {
        // Mutation: drop the literal rule. The pivot then comes from "www" alone, index 1, and the
        // other 27 characters hang off one side at a fraction of the size (TestFlight 1.4 (8)).
        let url = "www.gutenberg.org/ebooks/1952"
        let segments = ORPCalculator.segments(for: url)
        #expect(segments.before.count == url.count / 2)
        #expect(abs(segments.before.count - segments.after.count) <= 1)
    }

    @Test func aShortTokenWithDotsKeepsTheOrdinaryRule() {
        #expect(ORPCalculator.orpIndex(for: "www.x.org") == 1)
    }
}
