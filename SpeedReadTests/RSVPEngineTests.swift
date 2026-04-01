import Testing
import Foundation
@testable import SpeedRead

@Suite("RSVP Engine Tests")
struct RSVPEngineTests {

    @Test @MainActor func engineStartsIdle() {
        let engine = RSVPEngine()
        #expect(engine.state == .idle)
        #expect(engine.currentWord == "")
        #expect(engine.currentIndex == 0)
    }

    @Test @MainActor func loadWordsPreparesEngine() {
        let engine = RSVPEngine()
        engine.load(words: ["Hello", "world", "test"], startingAt: 0)
        #expect(engine.state == .paused)
        #expect(engine.currentWord == "Hello")
        #expect(engine.currentIndex == 0)
        #expect(engine.totalWords == 3)
    }

    @Test @MainActor func loadWordsAtOffset() {
        let engine = RSVPEngine()
        engine.load(words: ["Hello", "world", "test"], startingAt: 1)
        #expect(engine.currentWord == "world")
        #expect(engine.currentIndex == 1)
    }

    @Test @MainActor func seekToValidIndex() {
        let engine = RSVPEngine()
        engine.load(words: ["a", "b", "c", "d", "e"], startingAt: 0)
        engine.seek(to: 3)
        #expect(engine.currentIndex == 3)
        #expect(engine.currentWord == "d")
    }

    @Test @MainActor func seekClampsToBounds() {
        let engine = RSVPEngine()
        engine.load(words: ["a", "b", "c"], startingAt: 0)
        engine.seek(to: 100)
        #expect(engine.currentIndex == 2)
        engine.seek(to: -5)
        #expect(engine.currentIndex == 0)
    }

    @Test @MainActor func currentSegmentsMatchORP() {
        let engine = RSVPEngine()
        engine.load(words: ["reading"], startingAt: 0)
        let segments = engine.currentSegments
        #expect(segments.before == "re")
        #expect(segments.focus == "a")
        #expect(segments.after == "ding")
    }

    @Test @MainActor func defaultWPMIs300() {
        let engine = RSVPEngine()
        #expect(engine.wpm == 300)
    }

    @Test @MainActor func wpmCanBeAdjusted() {
        let engine = RSVPEngine()
        engine.wpm = 500
        #expect(engine.wpm == 500)
    }

    @Test @MainActor func wpmClampedToRange() {
        let engine = RSVPEngine()
        engine.wpm = 50
        #expect(engine.wpm == 100)
        engine.wpm = 2000
        #expect(engine.wpm == 1000)
    }

    @Test @MainActor func pauseWhileIdle() {
        let engine = RSVPEngine()
        engine.pause()
        #expect(engine.state == .idle)
    }

    @Test @MainActor func loadThenTogglePlaysAndPauses() {
        let engine = RSVPEngine()
        engine.load(words: ["a", "b", "c"], startingAt: 0)
        #expect(engine.state == .paused)
        engine.play()
        #expect(engine.state == .playing)
        engine.pause()
        #expect(engine.state == .paused)
    }
}
