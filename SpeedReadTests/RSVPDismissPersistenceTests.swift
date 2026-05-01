import Testing
import Foundation
@testable import SpeedRead

@Suite("RSVP dismiss preserves last-read index")
@MainActor
struct RSVPDismissPersistenceTests {

    @Test func pausePreservesCurrentIndex() {
        let engine = RSVPEngine()
        let words = ["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog."]
        engine.load(words: words, startingAt: 4)
        // Simulate the close path: pause then read the index.
        engine.pause()
        #expect(engine.currentIndex == 4)
        #expect(engine.totalWords == words.count)
        #expect(engine.isLoaded)
    }

    @Test func snapshotIndexAndPauseReturnsVisibleIndex() {
        let engine = RSVPEngine()
        engine.load(words: ["a", "b", "c", "d"], startingAt: 2)
        let snap = engine.snapshotIndexAndPause()
        #expect(snap == 2)
        #expect(engine.currentIndex == 2)
        #expect(engine.isLoaded)
    }

    @Test func stopClearsState() {
        let engine = RSVPEngine()
        engine.load(words: ["alpha", "beta"], startingAt: 1)
        engine.stop()
        #expect(engine.currentIndex == 0)
        #expect(engine.totalWords == 0)
    }

    @Test func loadAtIndexClampsAndExposesWord() {
        let engine = RSVPEngine()
        engine.load(words: ["one", "two", "three"], startingAt: 99)
        #expect(engine.currentIndex == 2)
        #expect(engine.currentWord == "three")
    }
}
