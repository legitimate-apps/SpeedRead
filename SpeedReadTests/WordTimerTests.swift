import Testing
@testable import SpeedRead

@Suite("Word Timer Tests")
struct WordTimerTests {

    @Test func baseDelayAt250WPM() {
        let timer = WordTimer(wpm: 250)
        #expect(timer.baseDelayMs == 240)
    }

    @Test func baseDelayAt300WPM() {
        let timer = WordTimer(wpm: 300)
        #expect(timer.baseDelayMs == 200)
    }

    @Test func baseDelayAt500WPM() {
        let timer = WordTimer(wpm: 500)
        #expect(timer.baseDelayMs == 120)
    }

    @Test func regularWordGetsBaseDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "hello")
        #expect(delay == 200)
    }

    @Test func periodEndsWithDoubleDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "done.")
        #expect(delay == 400)
    }

    @Test func questionMarkDoubleDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "what?")
        #expect(delay == 400)
    }

    @Test func exclamationDoubleDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "wow!")
        #expect(delay == 400)
    }

    @Test func commaGets1_5xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "well,")
        #expect(delay == 300)
    }

    @Test func semicolonGets1_5xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "here;")
        #expect(delay == 300)
    }

    @Test func colonGets1_5xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "note:")
        #expect(delay == 300)
    }

    @Test func longWordGets1_3xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "beautiful")
        #expect(delay == 260)
    }

    @Test func numberGets1_8xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "42")
        #expect(delay == 360)
    }

    @Test func numberWithTextGetsNoNumberBonus() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "hello")
        #expect(delay == 200)
    }

    @Test func longWordWithPeriodStacksMultipliers() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "beautiful.")
        #expect(delay == 520) // 200 * 1.3 * 2.0
    }

    @Test func updatingWPMChangesBaseDelay() {
        var timer = WordTimer(wpm: 300)
        #expect(timer.baseDelayMs == 200)
        timer.wpm = 600
        #expect(timer.baseDelayMs == 100)
    }
}
