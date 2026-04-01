//  RSVPIntegrationTests.swift

import Testing
import Foundation
@testable import SpeedRead

@Suite("RSVP Integration Tests")
struct RSVPIntegrationTests {

    @Test @MainActor func fullPipelineFromTextToPlayback() {
        let text = "The quick brown fox jumps over the lazy dog."
        let book = Book(
            title: "Test",
            author: "Author",
            extractedText: text,
            sourceFileName: "test.txt"
        )

        let words = book.words
        #expect(words.count == 9)

        let engine = RSVPEngine()
        engine.load(words: words, startingAt: 0)
        #expect(engine.state == .paused)
        #expect(engine.currentWord == "The")

        let theSegments = ORPCalculator.segments(for: "The")
        #expect(theSegments.before == "T")
        #expect(theSegments.focus == "h")
        #expect(theSegments.after == "e")

        let quickSegments = ORPCalculator.segments(for: "quick")
        #expect(quickSegments.before == "q")
        #expect(quickSegments.focus == "u")
        #expect(quickSegments.after == "ick")

        let timer = WordTimer(wpm: 300)
        let regularDelay = timer.delay(for: "quick")
        let sentenceEndDelay = timer.delay(for: "dog.")
        #expect(sentenceEndDelay > regularDelay)
        #expect(sentenceEndDelay == regularDelay * 2)

        engine.seek(to: 4)
        #expect(engine.currentWord == "jumps")

        engine.wpm = 500
        #expect(engine.wpm == 500)
    }

    @Test @MainActor func engineReachesEndOfText() async throws {
        let engine = RSVPEngine()
        engine.wpm = 1000
        engine.load(words: ["one", "two", "three"], startingAt: 0)
        engine.play()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(engine.state == .paused)
        #expect(engine.currentIndex == 2)
    }

    @Test func orpConsistencyAcrossWordLengths() {
        let testWords = [
            "I", "am", "the", "best", "quick", "reading", "absolute",
            "recognize", "understand", "presentation", "communication",
            "representations", "acknowledgements"
        ]

        for word in testWords {
            let idx = ORPCalculator.orpIndex(for: word)
            #expect(idx >= 0, "ORP index negative for '\(word)'")
            #expect(idx < word.count, "ORP index out of bounds for '\(word)'")

            let segments = ORPCalculator.segments(for: word)
            let reconstructed = segments.before + segments.focus + segments.after
            #expect(reconstructed == word, "Segments don't reconstruct '\(word)'")
        }
    }
}
