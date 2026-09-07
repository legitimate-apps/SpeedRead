import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Digital Crown seek mapping")
@MainActor
struct CrownSeekTests {

    // Reported by the operator 2026-08-29: stepping through words with the crown moved through the
    // book in the opposite direction to what they expected. The crown's bound value RISES as the
    // crown turns the way that reads as "back", so a higher crown value must land on an EARLIER
    // word. This is the assertion that fails against the original direct mapping.
    @Test func aHigherCrownValueLandsEarlierInTheBook() {
        #expect(CrownSeek.wordIndex(forCrownValue: 0, wordCount: 100) == 99)
        #expect(CrownSeek.wordIndex(forCrownValue: 99, wordCount: 100) == 0)
    }

    @Test func oneDetentOfCrownTravelMovesExactlyOneWord() {
        let a = CrownSeek.wordIndex(forCrownValue: 40, wordCount: 100)
        let b = CrownSeek.wordIndex(forCrownValue: 41, wordCount: 100)
        #expect(a - b == 1)
    }

    @Test func crownValueAndWordIndexAreExactInverses() {
        for index in [0, 1, 37, 98, 99] {
            let crown = CrownSeek.crownValue(forWordIndex: index, wordCount: 100)
            #expect(CrownSeek.wordIndex(forCrownValue: crown, wordCount: 100) == index)
        }
    }

    @Test func indexIsClampedInsideTheBook() {
        #expect(CrownSeek.wordIndex(forCrownValue: -50, wordCount: 100) == 99)
        #expect(CrownSeek.wordIndex(forCrownValue: 5_000, wordCount: 100) == 0)
    }

    @Test func aNonFiniteCrownValueCannotEscapeTheBook() {
        let index = CrownSeek.wordIndex(forCrownValue: .nan, wordCount: 100)
        #expect((0...99).contains(index))
    }

    @Test func degenerateBooksStayAtWordZero() {
        #expect(CrownSeek.wordIndex(forCrownValue: 0, wordCount: 0) == 0)
        #expect(CrownSeek.wordIndex(forCrownValue: 7, wordCount: 1) == 0)
        #expect(CrownSeek.crownValue(forWordIndex: 3, wordCount: 1) == 0)
    }

    @Test func theCrownAlwaysHasTravelToOffer() {
        #expect(CrownSeek.crownUpperBound(wordCount: 0) == 1)
        #expect(CrownSeek.crownUpperBound(wordCount: 1) == 1)
        #expect(CrownSeek.crownUpperBound(wordCount: 100) == 99)
    }
}
