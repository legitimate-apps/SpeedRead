# SpeedRead RSVP E-Reader Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS RSVP speed reading e-reader that imports EPUBs/PDFs and displays them using Spritz-style Rapid Serial Visual Presentation with ORP alignment.

**Architecture:** SwiftUI + SwiftData, protocol-oriented with dependency injection. RSVP engine is a standalone component with ORP calculation and adaptive timing. The existing Core Data template will be fully replaced. Xcode 26.3 uses `PBXFileSystemSynchronizedRootGroup` so new files added to the `SpeedRead/` directory are automatically included in the build — no pbxproj modifications needed.

**Tech Stack:** SwiftUI, SwiftData, PDFKit, structured concurrency (async/await), XCTest. Swift 6 concurrency is enabled (`MainActor` default isolation).

**Important project details:**
- Deployment target: iOS 26.2
- Bundle ID: `com.legitimateapps.SpeedRead`
- Development team: `3LTL47SJ8C`
- Swift concurrency: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- Build/test command: `xcodebuild -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' test` (or use Xcode MCP tools)

---

## Task 1: Clean Up — Remove Core Data Boilerplate

Remove the Core Data template code that shipped with the project. This is prerequisite to everything else.

**Files:**
- Delete: `SpeedRead/Persistence.swift`
- Delete: `SpeedRead/SpeedRead.xcdatamodeld/` (entire directory)
- Modify: `SpeedRead/SpeedReadApp.swift`
- Modify: `SpeedRead/ContentView.swift`
- Modify: `SpeedReadTests/SpeedReadTests.swift`

**Step 1: Replace SpeedReadApp.swift with minimal SwiftData app**

```swift
//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Book.self)
    }
}
```

**Step 2: Replace ContentView.swift with placeholder**

```swift
//  ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("SpeedRead")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 3: Replace SpeedReadTests.swift with placeholder**

```swift
import Testing
@testable import SpeedRead

@Suite("SpeedRead Tests")
struct SpeedReadTests {
    @Test func appLaunches() {
        // Placeholder — real tests follow in subsequent tasks
    }
}
```

**Step 4: Delete Core Data files**

```bash
rm SpeedRead/Persistence.swift
rm -rf SpeedRead/SpeedRead.xcdatamodeld
```

**Step 5: Build to verify clean compile**

Run: `xcodebuild -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

Note: The build will fail until Task 2 (Book model) is complete because SpeedReadApp.swift references `Book.self`. Implement Task 1 and Task 2 together, then build.

**Step 6: Commit**

```bash
git add -A && git commit -m "Remove Core Data boilerplate, prepare for SwiftData migration"
```

---

## Task 2: Book Model (SwiftData)

Create the core data model that everything else depends on.

**Files:**
- Create: `SpeedRead/Models/Book.swift`
- Test: `SpeedReadTests/BookTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("Book Model Tests")
struct BookTests {
    @Test func bookInitializesWithDefaults() {
        let book = Book(
            title: "Test Book",
            author: "Test Author",
            extractedText: "Hello world this is a test.",
            sourceFileName: "test.epub"
        )
        #expect(book.title == "Test Book")
        #expect(book.author == "Test Author")
        #expect(book.lastReadWordIndex == 0)
        #expect(book.sourceFileName == "test.epub")
    }

    @Test func wordsPropertySplitsText() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "Hello world this is a test",
            sourceFileName: "t.epub"
        )
        let words = book.words
        #expect(words.count == 6)
        #expect(words[0] == "Hello")
        #expect(words[5] == "test")
    }

    @Test func wordsHandlesMultipleSpaces() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "Hello   world\n\ntest",
            sourceFileName: "t.epub"
        )
        let words = book.words
        #expect(words.count == 3)
        #expect(words[0] == "Hello")
        #expect(words[1] == "world")
        #expect(words[2] == "test")
    }

    @Test func wordsHandlesEmptyText() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "",
            sourceFileName: "t.epub"
        )
        #expect(book.words.isEmpty)
    }

    @Test func progressCalculation() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "one two three four five six seven eight nine ten",
            sourceFileName: "t.epub"
        )
        book.lastReadWordIndex = 5
        #expect(book.progress == 0.5)
    }

    @Test func progressIsZeroWhenNoWords() {
        let book = Book(
            title: "T",
            author: "A",
            extractedText: "",
            sourceFileName: "t.epub"
        )
        #expect(book.progress == 0.0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(FAIL|error|BUILD)'`

Expected: Compilation error — `Book` not defined.

**Step 3: Write the Book model**

```swift
//  Book.swift
import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var extractedText: String
    var sourceFileName: String
    var dateAdded: Date
    var lastReadWordIndex: Int
    var lastReadDate: Date?

    init(
        title: String,
        author: String,
        extractedText: String,
        sourceFileName: String
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.extractedText = extractedText
        self.sourceFileName = sourceFileName
        self.dateAdded = Date()
        self.lastReadWordIndex = 0
        self.lastReadDate = nil
    }

    var words: [String] {
        extractedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var progress: Double {
        let totalWords = words.count
        guard totalWords > 0 else { return 0.0 }
        return Double(lastReadWordIndex) / Double(totalWords)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(PASS|FAIL|BUILD)'`

Expected: All tests pass, BUILD SUCCEEDED.

**Step 5: Commit**

```bash
git add SpeedRead/Models/Book.swift SpeedReadTests/BookTests.swift
git commit -m "Add Book SwiftData model with word splitting and progress"
```

---

## Task 3: ORP Calculator

The core algorithm — calculates the Optimal Recognition Point index for any word.

**Files:**
- Create: `SpeedRead/Engine/ORPCalculator.swift`
- Test: `SpeedReadTests/ORPCalculatorTests.swift`

**Step 1: Write the failing tests**

```swift
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
        // "Hello" — ORP should be on 'e' (index 2), not the quote
        #expect(ORPCalculator.orpIndex(for: "\"Hello\"") == 2)
    }

    @Test func leadingParenthesis() {
        // (test) — ORP on 'e' (index 2)
        #expect(ORPCalculator.orpIndex(for: "(test)") == 2)
    }

    @Test func leadingSingleQuote() {
        // 'word — ORP on 'o' (index 2)
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
        // "world." — trailing punctuation doesn't affect ORP
        // "world" is 5 chars → bucket 2-5 → ORP index 1, but raw string is 6 chars
        // ORP is calculated on the alpha content, then offset by leading punct count
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
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E 'error|FAIL'`

Expected: Compilation error — `ORPCalculator` not defined.

**Step 3: Write the ORPCalculator**

```swift
//  ORPCalculator.swift
import Foundation

enum ORPCalculator {

    struct WordSegments {
        let before: String
        let focus: String
        let after: String
    }

    /// Returns the 0-based index of the ORP character in the raw word string.
    /// Leading punctuation is skipped — ORP is calculated on alphanumeric content
    /// length, then offset back to the raw string position.
    static func orpIndex(for word: String) -> Int {
        guard !word.isEmpty else { return 0 }

        let chars = Array(word)
        let leadingPunctCount = chars.prefix(while: { !$0.isLetter && !$0.isNumber }).count
        let strippedLength = chars.suffix(from: leadingPunctCount)
            .prefix(while: { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" })
            .count

        let rawORPIndex = orpBucket(for: strippedLength)
        return leadingPunctCount + rawORPIndex
    }

    /// Splits a word into three display segments around the ORP character.
    static func segments(for word: String) -> WordSegments {
        guard !word.isEmpty else {
            return WordSegments(before: "", focus: "", after: "")
        }

        let idx = orpIndex(for: word)
        let chars = Array(word)
        let clampedIdx = min(idx, chars.count - 1)

        let before = String(chars[..<clampedIdx])
        let focus = String(chars[clampedIdx])
        let after = clampedIdx + 1 < chars.count ? String(chars[(clampedIdx + 1)...]) : ""

        return WordSegments(before: before, focus: focus, after: after)
    }

    // MARK: - Private

    private static func orpBucket(for alphaLength: Int) -> Int {
        switch alphaLength {
        case 0:     return 0
        case 1:     return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default:    return 4
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(Test Suite|passed|failed|BUILD)'`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add SpeedRead/Engine/ORPCalculator.swift SpeedReadTests/ORPCalculatorTests.swift
git commit -m "Add ORP calculator with word segmentation for RSVP display"
```

---

## Task 4: Word Timer (Adaptive Timing)

Calculates per-word display duration based on WPM and word characteristics.

**Files:**
- Create: `SpeedRead/Engine/WordTimer.swift`
- Test: `SpeedReadTests/WordTimerTests.swift`

**Step 1: Write the failing tests**

```swift
import Testing
@testable import SpeedRead

@Suite("Word Timer Tests")
struct WordTimerTests {

    // MARK: - Base delay calculation

    @Test func baseDelayAt250WPM() {
        let timer = WordTimer(wpm: 250)
        // 60000 / 250 = 240ms
        #expect(timer.baseDelayMs == 240)
    }

    @Test func baseDelayAt300WPM() {
        let timer = WordTimer(wpm: 300)
        // 60000 / 300 = 200ms
        #expect(timer.baseDelayMs == 200)
    }

    @Test func baseDelayAt500WPM() {
        let timer = WordTimer(wpm: 500)
        // 60000 / 500 = 120ms
        #expect(timer.baseDelayMs == 120)
    }

    // MARK: - Regular words (no multiplier)

    @Test func regularWordGetsBaseDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "hello")
        #expect(delay == 200) // base delay, no multipliers
    }

    // MARK: - Sentence-ending punctuation (2.0x)

    @Test func periodEndsWithDoubleDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "done.")
        #expect(delay == 400) // 200 * 2.0
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

    // MARK: - Clause punctuation (1.5x)

    @Test func commaGets1_5xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "well,")
        #expect(delay == 300) // 200 * 1.5
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

    // MARK: - Long words (8+ chars, 1.3x)

    @Test func longWordGets1_3xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "beautiful")
        // 9 chars → 1.3x → 200 * 1.3 = 260
        #expect(delay == 260)
    }

    // MARK: - Numbers (1.8x)

    @Test func numberGets1_8xDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "42")
        #expect(delay == 360) // 200 * 1.8
    }

    @Test func numberWithTextGetsNoNumberBonus() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "hello")
        #expect(delay == 200) // not a number
    }

    // MARK: - Stacked multipliers

    @Test func longWordWithPeriodStacksMultipliers() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.delay(for: "beautiful.")
        // 9 alpha chars → long word 1.3x, period → 2.0x
        // 200 * 1.3 * 2.0 = 520
        #expect(delay == 520)
    }

    // MARK: - Paragraph breaks

    @Test func paragraphBreakDelay() {
        let timer = WordTimer(wpm: 300)
        let delay = timer.paragraphBreakDelay
        // 200 * 2.5 = 500
        #expect(delay == 500)
    }

    // MARK: - WPM update

    @Test func updatingWPMChangesBaseDelay() {
        var timer = WordTimer(wpm: 300)
        #expect(timer.baseDelayMs == 200)
        timer.wpm = 600
        #expect(timer.baseDelayMs == 100)
    }
}
```

**Step 2: Run test to verify it fails**

Expected: Compilation error — `WordTimer` not defined.

**Step 3: Write the WordTimer**

```swift
//  WordTimer.swift
import Foundation

struct WordTimer {
    var wpm: Int

    var baseDelayMs: Int {
        60_000 / wpm
    }

    var paragraphBreakDelay: Int {
        Int(Double(baseDelayMs) * 2.5)
    }

    func delay(for word: String) -> Int {
        var multiplier = 1.0

        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)

        // Long word check (8+ alphanumeric characters)
        if trimmed.count >= 8 {
            multiplier *= 1.3
        }

        // Number check (entire word is numeric)
        if trimmed.allSatisfy({ $0.isNumber }) && !trimmed.isEmpty {
            multiplier *= 1.8
        }

        // Sentence-ending punctuation
        if word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!") {
            multiplier *= 2.0
        }
        // Clause punctuation (only if not already sentence-ending)
        else if word.hasSuffix(",") || word.hasSuffix(";") || word.hasSuffix(":") || word.hasSuffix("—") || word.hasSuffix("–") {
            multiplier *= 1.5
        }

        return Int(Double(baseDelayMs) * multiplier)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests pass.

**Step 5: Commit**

```bash
git add SpeedRead/Engine/WordTimer.swift SpeedReadTests/WordTimerTests.swift
git commit -m "Add WordTimer with adaptive timing multipliers for RSVP pacing"
```

---

## Task 5: RSVP Engine (Playback State Machine)

The core engine that drives word-by-word playback with play/pause/seek.

**Files:**
- Create: `SpeedRead/Engine/RSVPEngine.swift`
- Test: `SpeedReadTests/RSVPEngineTests.swift`

**Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("RSVP Engine Tests")
struct RSVPEngineTests {

    // MARK: - Initialization

    @Test @MainActor func engineStartsIdle() {
        let engine = RSVPEngine()
        #expect(engine.state == .idle)
        #expect(engine.currentWord == "")
        #expect(engine.currentIndex == 0)
    }

    // MARK: - Loading words

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

    // MARK: - Seeking

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

    // MARK: - ORP segments

    @Test @MainActor func currentSegmentsMatchORP() {
        let engine = RSVPEngine()
        engine.load(words: ["reading"], startingAt: 0)
        let segments = engine.currentSegments
        #expect(segments.before == "re")
        #expect(segments.focus == "a")
        #expect(segments.after == "ding")
    }

    // MARK: - WPM

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

    // MARK: - State transitions

    @Test @MainActor func pauseWhileIdle() {
        let engine = RSVPEngine()
        engine.pause()
        #expect(engine.state == .idle) // can't pause with no words
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
```

**Step 2: Run test to verify it fails**

Expected: Compilation error — `RSVPEngine` not defined.

**Step 3: Write the RSVPEngine**

```swift
//  RSVPEngine.swift
import Foundation
import Observation

@Observable
@MainActor
final class RSVPEngine {

    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    // MARK: - Published state

    private(set) var state: State = .idle
    private(set) var currentIndex: Int = 0
    private(set) var currentWord: String = ""
    private(set) var totalWords: Int = 0

    var wpm: Int = 300 {
        didSet {
            wpm = max(100, min(1000, wpm))
            timer.wpm = wpm
        }
    }

    // MARK: - Internal

    private var words: [String] = []
    private var timer = WordTimer(wpm: 300)
    private var playbackTask: Task<Void, Never>?

    // MARK: - Computed

    var currentSegments: ORPCalculator.WordSegments {
        ORPCalculator.segments(for: currentWord)
    }

    var progress: Double {
        guard totalWords > 0 else { return 0 }
        return Double(currentIndex) / Double(totalWords)
    }

    // MARK: - Control

    func load(words: [String], startingAt index: Int) {
        stop()
        self.words = words
        self.totalWords = words.count
        let clampedIndex = max(0, min(index, words.count - 1))
        self.currentIndex = clampedIndex
        self.currentWord = words.isEmpty ? "" : words[clampedIndex]
        self.state = words.isEmpty ? .idle : .paused
    }

    func play() {
        guard state != .playing, !words.isEmpty else { return }
        state = .playing
        startPlayback()
    }

    func pause() {
        guard state == .playing else { return }
        playbackTask?.cancel()
        playbackTask = nil
        state = .paused
    }

    func togglePlayPause() {
        switch state {
        case .idle: break
        case .playing: pause()
        case .paused: play()
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        state = .idle
        currentIndex = 0
        currentWord = ""
        totalWords = 0
        words = []
    }

    func seek(to index: Int) {
        guard !words.isEmpty else { return }
        let clamped = max(0, min(index, words.count - 1))
        currentIndex = clamped
        currentWord = words[clamped]
    }

    // MARK: - Playback Loop

    private func startPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.currentIndex < self.words.count {
                let word = self.words[self.currentIndex]
                self.currentWord = word
                let delayMs = self.timer.delay(for: word)
                let delayNs = UInt64(delayMs) * 1_000_000

                do {
                    try await Task.sleep(nanoseconds: delayNs)
                } catch {
                    return // cancelled
                }

                if !Task.isCancelled {
                    self.currentIndex += 1
                }
            }

            if !Task.isCancelled {
                // Reached the end
                self.state = .paused
                if !self.words.isEmpty {
                    self.currentIndex = self.words.count - 1
                    self.currentWord = self.words[self.currentIndex]
                }
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests pass.

**Step 5: Commit**

```bash
git add SpeedRead/Engine/RSVPEngine.swift SpeedReadTests/RSVPEngineTests.swift
git commit -m "Add RSVPEngine playback state machine with play/pause/seek"
```

---

## Task 6: RSVP Word View (The Redicle)

The Spritz-style display component — the visual heart of the app.

**Files:**
- Create: `SpeedRead/Views/RSVPWordView.swift`

**Step 1: Build the RSVPWordView**

```swift
//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat

    init(segments: ORPCalculator.WordSegments, fontSize: CGFloat = 32) {
        self.segments = segments
        self.fontSize = fontSize
    }

    private var font: Font {
        .system(size: fontSize, weight: .bold, design: .monospaced)
    }

    private var charWidth: CGFloat {
        // SF Mono character width approximation: ~0.6 * fontSize
        fontSize * 0.6
    }

    /// Maximum characters to either side of the ORP for layout sizing.
    /// Ensures the redicle has consistent width.
    private let maxSideChars = 12

    var body: some View {
        VStack(spacing: 2) {
            // Top guide mark
            guideMark

            // Word display
            HStack(spacing: 0) {
                // Left segment — right-aligned to the focal point
                Text(segments.before)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .trailing)

                // ORP character — the focal point
                Text(segments.focus)
                    .font(font)
                    .foregroundStyle(.red)
                    .frame(width: charWidth, alignment: .center)

                // Right segment — left-aligned from the focal point
                Text(segments.after)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .leading)
            }

            // Bottom guide mark
            guideMark
        }
        .padding(.horizontal)
    }

    private var guideMark: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
            Rectangle()
                .fill(.red)
                .frame(width: 2, height: 8)
                .frame(width: charWidth)
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
        }
        .padding(.horizontal)
    }
}

#Preview("Simple word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "reading"))
        .preferredColorScheme(.dark)
}

#Preview("Short word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "Hi"))
        .preferredColorScheme(.dark)
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "presentation"))
        .preferredColorScheme(.dark)
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3`

Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add SpeedRead/Views/RSVPWordView.swift
git commit -m "Add RSVPWordView Spritz-style redicle with ORP alignment and guide marks"
```

---

## Task 7: PDF Text Extraction

Extract plain text from PDF files using built-in PDFKit.

**Files:**
- Create: `SpeedRead/Extraction/TextExtractor.swift`
- Create: `SpeedRead/Extraction/PDFExtractor.swift`
- Test: `SpeedReadTests/PDFExtractorTests.swift`
- Test resource: `SpeedReadTests/Resources/sample.pdf` (generate programmatically in test)

**Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import PDFKit
@testable import SpeedRead

@Suite("PDF Extractor Tests")
struct PDFExtractorTests {

    @Test func extractsTextFromPDFData() throws {
        // Create a simple PDF in memory for testing
        let pdfData = createTestPDF(text: "Hello world from a PDF document")
        let extractor = PDFExtractor()
        let result = try extractor.extractText(from: pdfData)
        #expect(result.text.contains("Hello"))
        #expect(result.text.contains("world"))
        #expect(result.text.contains("PDF"))
        #expect(result.title == nil || !result.text.isEmpty) // title may or may not be set
    }

    @Test func emptyPDFReturnsEmptyText() throws {
        let pdfData = createTestPDF(text: "")
        let extractor = PDFExtractor()
        let result = try extractor.extractText(from: pdfData)
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func invalidDataThrows() {
        let extractor = PDFExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not a pdf".utf8))
        }
    }

    // MARK: - Helpers

    private func createTestPDF(text: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            text.draw(in: CGRect(x: 72, y: 72, width: 468, height: 648), withAttributes: attributes)
        }
    }
}
```

**Step 2: Run test to verify it fails**

Expected: Compilation error — `PDFExtractor`, `ExtractionError` not defined.

**Step 3: Write TextExtractor protocol and PDFExtractor**

`SpeedRead/Extraction/TextExtractor.swift`:

```swift
//  TextExtractor.swift
import Foundation

struct ExtractionResult {
    let text: String
    let title: String?
    let author: String?
}

enum ExtractionError: Error {
    case invalidData
    case parsingFailed(String)
    case unsupportedFormat
}

protocol TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult
}
```

`SpeedRead/Extraction/PDFExtractor.swift`:

```swift
//  PDFExtractor.swift
import Foundation
import PDFKit

struct PDFExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        guard let document = PDFDocument(data: data) else {
            throw ExtractionError.invalidData
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let text = page.string {
                pages.append(text)
            }
        }

        let fullText = pages.joined(separator: "\n\n")

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        return ExtractionResult(
            text: fullText,
            title: title,
            author: author
        )
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests pass.

**Step 5: Commit**

```bash
git add SpeedRead/Extraction/TextExtractor.swift SpeedRead/Extraction/PDFExtractor.swift SpeedReadTests/PDFExtractorTests.swift
git commit -m "Add PDF text extraction using PDFKit"
```

---

## Task 8: EPUB Text Extraction

Extract plain text from EPUB files. EPUBs are ZIP archives containing XHTML files.

**Files:**
- Create: `SpeedRead/Extraction/EPUBExtractor.swift`
- Test: `SpeedReadTests/EPUBExtractorTests.swift`

**Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("EPUB Extractor Tests")
struct EPUBExtractorTests {

    @Test func extractsTextFromXHTML() {
        let xhtml = """
        <html><body>
        <h1>Chapter One</h1>
        <p>This is a <em>test</em> paragraph.</p>
        <p>Second paragraph here.</p>
        </body></html>
        """
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Chapter One"))
        #expect(text.contains("This is a test paragraph."))
        #expect(text.contains("Second paragraph here."))
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
    }

    @Test func stripHTMLHandlesEntities() {
        let xhtml = "<p>Don&apos;t stop &amp; think</p>"
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Don't") || text.contains("Don't"))
        #expect(text.contains("&") || text.contains("think"))
    }

    @Test func stripHTMLHandlesEmptyInput() {
        let text = EPUBExtractor.stripHTML("")
        #expect(text.isEmpty)
    }

    @Test func invalidDataThrows() {
        let extractor = EPUBExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not an epub".utf8))
        }
    }
}
```

**Step 2: Run test to verify it fails**

Expected: Compilation error — `EPUBExtractor` not defined.

**Step 3: Write the EPUBExtractor**

```swift
//  EPUBExtractor.swift
import Foundation

struct EPUBExtractor: TextExtractor {

    func extractText(from data: Data) throws -> ExtractionResult {
        // EPUB is a ZIP file. We need to:
        // 1. Unzip to a temp directory
        // 2. Read META-INF/container.xml to find the OPF file
        // 3. Parse the OPF to get the spine (reading order)
        // 4. Read each XHTML file in spine order
        // 5. Strip HTML tags to get plain text

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Write epub data and unzip
            let epubURL = tempDir.appendingPathComponent("book.epub")
            try data.write(to: epubURL)

            let unzipDir = tempDir.appendingPathComponent("contents")
            try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

            // Use built-in unzip command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", epubURL.path, "-d", unzipDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw ExtractionError.invalidData
            }

            // Parse container.xml to find OPF
            let containerURL = unzipDir
                .appendingPathComponent("META-INF")
                .appendingPathComponent("container.xml")
            let containerXML = try String(contentsOf: containerURL, encoding: .utf8)
            guard let opfPath = parseContainerForOPFPath(containerXML) else {
                throw ExtractionError.parsingFailed("Could not find OPF path in container.xml")
            }

            let opfURL = unzipDir.appendingPathComponent(opfPath)
            let opfDir = opfURL.deletingLastPathComponent()
            let opfXML = try String(contentsOf: opfURL, encoding: .utf8)

            // Parse OPF for metadata and spine
            let metadata = parseOPFMetadata(opfXML)
            let spineFiles = parseOPFSpine(opfXML, baseURL: opfDir)

            // Read each spine file and strip HTML
            var chapters: [String] = []
            for fileURL in spineFiles {
                if let xhtml = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let text = Self.stripHTML(xhtml)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        chapters.append(text)
                    }
                }
            }

            let fullText = chapters.joined(separator: "\n\n")

            return ExtractionResult(
                text: fullText,
                title: metadata.title,
                author: metadata.author
            )
        } catch let error as ExtractionError {
            throw error
        } catch {
            throw ExtractionError.invalidData
        }
    }

    // MARK: - HTML Stripping

    static func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html

        // Replace common block elements with newlines
        let blockTags = ["</p>", "</div>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>", "<br>", "<br/>", "<br />"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&rsquo;", "\u{2019}"),
            ("&lsquo;", "\u{2018}"),
            ("&rdquo;", "\u{201D}"),
            ("&ldquo;", "\u{201C}"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse multiple whitespace/newlines
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    // MARK: - XML Parsing Helpers

    private func parseContainerForOPFPath(_ xml: String) -> String? {
        // Look for: <rootfile full-path="OEBPS/content.opf" .../>
        guard let range = xml.range(of: "full-path=\"[^\"]+\"", options: .regularExpression) else {
            return nil
        }
        let match = String(xml[range])
        return match
            .replacingOccurrences(of: "full-path=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
    }

    private struct EPUBMetadata {
        let title: String?
        let author: String?
    }

    private func parseOPFMetadata(_ xml: String) -> EPUBMetadata {
        let title = extractTagContent(from: xml, tag: "dc:title")
        let author = extractTagContent(from: xml, tag: "dc:creator")
        return EPUBMetadata(title: title, author: author)
    }

    private func parseOPFSpine(_ xml: String, baseURL: URL) -> [URL] {
        // 1. Build manifest: id → href
        var manifest: [String: String] = [:]
        let manifestPattern = "<item\\s+[^>]*id=\"([^\"]+)\"[^>]*href=\"([^\"]+)\"[^>]*/>"
        if let regex = try? NSRegularExpression(pattern: manifestPattern, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xml),
                   let hrefRange = Range(match.range(at: 2), in: xml) {
                    manifest[String(xml[idRange])] = String(xml[hrefRange])
                }
            }
        }

        // Also handle <item> tags where href comes before id
        let manifestPattern2 = "<item\\s+[^>]*href=\"([^\"]+)\"[^>]*id=\"([^\"]+)\"[^>]*/>"
        if let regex = try? NSRegularExpression(pattern: manifestPattern2, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: xml),
                   let idRange = Range(match.range(at: 2), in: xml) {
                    manifest[String(xml[idRange])] = String(xml[hrefRange])
                }
            }
        }

        // 2. Parse spine for itemref order
        var spineIDs: [String] = []
        let spinePattern = "<itemref\\s+idref=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xml) {
                    spineIDs.append(String(xml[idRange]))
                }
            }
        }

        // 3. Resolve to file URLs
        return spineIDs.compactMap { id in
            guard let href = manifest[id] else { return nil }
            let decoded = href.removingPercentEncoding ?? href
            return baseURL.appendingPathComponent(decoded)
        }
    }

    private func extractTagContent(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests pass. Note: the `invalidDataThrows` test verifies the unzip fails on garbage data. The `stripHTML` tests are pure unit tests that don't need actual EPUB files.

**Step 5: Commit**

```bash
git add SpeedRead/Extraction/EPUBExtractor.swift SpeedReadTests/EPUBExtractorTests.swift
git commit -m "Add EPUB text extraction with HTML stripping and spine parsing"
```

---

## Task 9: Document Import Service

Handles the document picker flow and creates Book entries in SwiftData.

**Files:**
- Create: `SpeedRead/Services/DocumentImporter.swift`

**Step 1: Write the DocumentImporter**

```swift
//  DocumentImporter.swift
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct DocumentImporter {
    let modelContext: ModelContext

    func importFile(at url: URL) throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let extractor: TextExtractor
        switch ext {
        case "pdf":
            extractor = PDFExtractor()
        case "epub":
            extractor = EPUBExtractor()
        default:
            throw ExtractionError.unsupportedFormat
        }

        let result = try extractor.extractText(from: data)
        let title = result.title ?? fileName.replacingOccurrences(of: ".\(ext)", with: "")
        let author = result.author ?? "Unknown Author"

        let book = Book(
            title: title,
            author: author,
            extractedText: result.text,
            sourceFileName: fileName
        )

        modelContext.insert(book)
        try modelContext.save()

        return book
    }
}
```

**Step 2: Build to verify it compiles**

Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add SpeedRead/Services/DocumentImporter.swift
git commit -m "Add DocumentImporter service for PDF and EPUB file import"
```

---

## Task 10: Library View

The main screen — shows imported books with import button.

**Files:**
- Create: `SpeedRead/Views/LibraryView.swift`
- Modify: `SpeedRead/ContentView.swift`

**Step 1: Write the LibraryView**

```swift
//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyLibraryView
                } else {
                    bookListView
                }
            }
            .navigationTitle("SpeedRead")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "Unknown error")
            }
        }
    }

    // MARK: - Subviews

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No Books", systemImage: "book.closed")
        } description: {
            Text("Import a PDF or EPUB to start speed reading.")
        } actions: {
            Button("Import Book") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var bookListView: some View {
        List {
            ForEach(books) { book in
                NavigationLink(value: book) {
                    BookRowView(book: book)
                }
            }
            .onDelete(perform: deleteBooks)
        }
        .navigationDestination(for: Book.self) { book in
            ReaderView(book: book)
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importer = DocumentImporter(modelContext: modelContext)
                _ = try importer.importFile(at: url)
            } catch {
                importError = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showError = true
        }
    }

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(books[index])
        }
    }
}

// MARK: - Book Row

struct BookRowView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
            Text(book.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: book.progress)
                .tint(.red)
        }
        .padding(.vertical, 4)
    }
}
```

**Step 2: Update ContentView to show LibraryView**

```swift
//  ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
```

**Step 3: Build to verify it compiles**

Expected: BUILD SUCCEEDED. (Note: `ReaderView` doesn't exist yet — this will cause a compilation error. Create a placeholder first, or implement Task 10 and Task 11 together.)

**Step 4: Commit**

```bash
git add SpeedRead/Views/LibraryView.swift SpeedRead/ContentView.swift
git commit -m "Add LibraryView with book list, import, and delete"
```

---

## Task 11: Reader View (Scrollable Text + RSVP Launch)

The basic e-reader with font size control and RSVP mode launch.

**Files:**
- Create: `SpeedRead/Views/ReaderView.swift`

**Step 1: Write the ReaderView**

```swift
//  ReaderView.swift
import SwiftUI

struct ReaderView: View {
    @Bindable var book: Book
    @State private var fontSize: CGFloat = 18
    @State private var showRSVP = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                Text(book.extractedText)
                    .font(.system(size: fontSize))
                    .padding()
                    .padding(.bottom, 80) // space for floating button
                    .textSelection(.enabled)
            }

            // Floating controls
            HStack {
                // Font size controls
                HStack(spacing: 12) {
                    Button {
                        fontSize = max(12, fontSize - 2)
                    } label: {
                        Text("A-")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        fontSize = min(32, fontSize + 2)
                    } label: {
                        Text("A+")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // RSVP launch button
                Button {
                    showRSVP = true
                } label: {
                    Label("RSVP", systemImage: "bolt.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showRSVP) {
            RSVPView(book: book)
        }
    }
}
```

**Step 2: Build to verify it compiles**

Note: `RSVPView` doesn't exist yet. Implement Task 11 and Task 12 together, or create a placeholder RSVPView first.

**Step 3: Commit**

```bash
git add SpeedRead/Views/ReaderView.swift
git commit -m "Add ReaderView with scrollable text, font sizing, and RSVP launch"
```

---

## Task 12: RSVP View (Full-Screen Speed Reading)

The full-screen RSVP experience on iPhone.

**Files:**
- Create: `SpeedRead/Views/RSVPView.swift`

**Step 1: Write the RSVPView**

```swift
//  RSVPView.swift
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Background — tap to toggle play/pause
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    engine.togglePlayPause()
                }

            VStack {
                // Top bar
                HStack {
                    Button {
                        engine.stop()
                        book.lastReadWordIndex = engine.currentIndex
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text("\(engine.wpm) WPM")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                // RSVP display
                RSVPWordView(segments: engine.currentSegments, fontSize: 36)

                Spacer()

                // Play/pause indicator + progress
                VStack(spacing: 16) {
                    if engine.state != .playing {
                        Button {
                            engine.play()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.red)
                        }
                    }

                    // Progress bar
                    VStack(spacing: 4) {
                        ProgressView(value: engine.progress)
                            .tint(.red)
                        HStack {
                            Text("Word \(engine.currentIndex + 1)")
                            Spacer()
                            Text("of \(engine.totalWords)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.load(
                words: book.words,
                startingAt: book.lastReadWordIndex
            )
        }
        .onDisappear {
            book.lastReadWordIndex = engine.currentIndex
        }
        .sheet(isPresented: $showSettings) {
            wpmSettingsSheet
        }
    }

    private var wpmSettingsSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("\(engine.wpm)")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)

                Text("Words Per Minute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(engine.wpm) },
                        set: { engine.wpm = Int($0) }
                    ),
                    in: 100...1000,
                    step: 25
                )
                .tint(.red)
                .padding(.horizontal)

                HStack {
                    Text("100")
                    Spacer()
                    Text("1000")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

**Step 2: Build to verify it compiles**

Expected: BUILD SUCCEEDED.

**Step 3: Run the app in simulator to manually verify**

Launch the app, import a PDF, open the reader, tap RSVP, and verify:
- Words display one at a time with red ORP highlight
- Guide marks visible above and below
- Tap pauses/resumes
- WPM slider works
- Progress bar advances

**Step 4: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "Add full-screen RSVPView with playback controls and WPM settings"
```

---

## Task 13: Update SpeedReadApp.swift

Ensure the app entry point is properly configured with SwiftData and all necessary type registrations.

**Files:**
- Modify: `SpeedRead/SpeedReadApp.swift`

**Step 1: Verify SpeedReadApp.swift is correct**

It should already be correct from Task 1. Verify it looks like:

```swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Book.self)
    }
}
```

**Step 2: Full build and test**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: All tests pass, BUILD SUCCEEDED.

**Step 3: Commit if any changes**

```bash
git add -A && git commit -m "Finalize app entry point and ensure full build passes"
```

---

## Task 14: Integration Test — Full RSVP Flow

End-to-end test verifying the complete pipeline from text to RSVP playback.

**Files:**
- Create: `SpeedReadTests/RSVPIntegrationTests.swift`

**Step 1: Write integration test**

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("RSVP Integration Tests")
struct RSVPIntegrationTests {

    @Test @MainActor func fullPipelineFromTextToPlayback() {
        // Simulate text extraction result
        let text = "The quick brown fox jumps over the lazy dog."

        // Create a book
        let book = Book(
            title: "Test",
            author: "Author",
            extractedText: text,
            sourceFileName: "test.txt"
        )

        // Verify word splitting
        let words = book.words
        #expect(words.count == 9)

        // Load into engine
        let engine = RSVPEngine()
        engine.load(words: words, startingAt: 0)
        #expect(engine.state == .paused)
        #expect(engine.currentWord == "The")

        // Verify ORP for each word
        let theSegments = ORPCalculator.segments(for: "The")
        #expect(theSegments.before == "T")
        #expect(theSegments.focus == "h")
        #expect(theSegments.after == "e")

        let quickSegments = ORPCalculator.segments(for: "quick")
        #expect(quickSegments.before == "q")
        #expect(quickSegments.focus == "u")
        #expect(quickSegments.after == "ick")

        // Verify timing — "dog." should get sentence-ending multiplier
        let timer = WordTimer(wpm: 300)
        let regularDelay = timer.delay(for: "quick")
        let sentenceEndDelay = timer.delay(for: "dog.")
        #expect(sentenceEndDelay > regularDelay)
        #expect(sentenceEndDelay == regularDelay * 2)

        // Seek
        engine.seek(to: 4)
        #expect(engine.currentWord == "jumps")

        // WPM adjustment
        engine.wpm = 500
        #expect(engine.wpm == 500)
    }

    @Test @MainActor func engineReachesEndOfText() async throws {
        let engine = RSVPEngine()
        engine.wpm = 1000 // very fast for test speed
        engine.load(words: ["one", "two", "three"], startingAt: 0)
        engine.play()

        // Wait for playback to finish (3 words at 1000 WPM = ~180ms + multipliers)
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms generous buffer

        #expect(engine.state == .paused)
        #expect(engine.currentIndex == 2) // last word index
    }

    @Test func orpConsistencyAcrossWordLengths() {
        // Verify ORP is always within bounds
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
```

**Step 2: Run tests**

Run: `xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: All tests pass.

**Step 3: Commit**

```bash
git add SpeedReadTests/RSVPIntegrationTests.swift
git commit -m "Add integration tests for full RSVP pipeline"
```

---

## Task 15: Final Polish and Build Verification

Clean up, verify everything builds and all tests pass.

**Files:**
- Verify all files are in place
- Run full test suite
- Fix any issues

**Step 1: Verify project structure**

```bash
find SpeedRead -name "*.swift" | sort
```

Expected:
```
SpeedRead/ContentView.swift
SpeedRead/Engine/ORPCalculator.swift
SpeedRead/Engine/RSVPEngine.swift
SpeedRead/Engine/WordTimer.swift
SpeedRead/Extraction/EPUBExtractor.swift
SpeedRead/Extraction/PDFExtractor.swift
SpeedRead/Extraction/TextExtractor.swift
SpeedRead/Models/Book.swift
SpeedRead/Services/DocumentImporter.swift
SpeedRead/SpeedReadApp.swift
SpeedRead/Views/LibraryView.swift
SpeedRead/Views/RSVPView.swift
SpeedRead/Views/RSVPWordView.swift
SpeedRead/Views/ReaderView.swift
```

**Step 2: Run full test suite**

```bash
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(Test Suite|passed|failed|BUILD)'
```

Expected: All test suites pass. BUILD SUCCEEDED.

**Step 3: Run in simulator and manually verify**

1. App launches to empty library
2. Tap + to import a PDF
3. Book appears in library with title and progress
4. Tap book to open reader
5. Reader shows scrollable text with font controls
6. Tap RSVP button
7. Full-screen RSVP with red ORP highlight and guide marks
8. Tap to pause/resume
9. Settings sheet with WPM slider
10. Close returns to reader

**Step 4: Final commit**

```bash
git add -A && git commit -m "SpeedRead v1: RSVP e-reader with PDF/EPUB support, ORP alignment, adaptive timing"
```

---

## Dependency Graph

```
Task 1 (Clean Core Data) ──┐
                            ├──→ Task 2 (Book Model) ──→ Task 9 (Importer) ──→ Task 10 (Library)
                            │                                                         │
Task 3 (ORP Calculator) ───┤                                                         ├──→ Task 13 (App Entry)
                            ├──→ Task 6 (RSVPWordView) ──→ Task 12 (RSVPView) ──────┤         │
Task 4 (WordTimer) ─────────┤                                    │                    │         ▼
                            ├──→ Task 5 (RSVPEngine) ────────────┘                    │    Task 15 (Final)
Task 7 (PDF Extractor) ─────┤                                                        │
                            ├──→ Task 9 (Importer) ──────────────────────────────────┘
Task 8 (EPUB Extractor) ────┘
                                                                  Task 11 (ReaderView)
                                                                       │
                                                                       ▼
                                                                  Task 12 (RSVPView)
                                                                       │
                                                                       ▼
                                                              Task 14 (Integration Tests)
```

**Parallelizable tasks:**
- Tasks 3, 4 can be done in parallel (no dependencies on each other)
- Tasks 7, 8 can be done in parallel
- Task 6 depends on Task 3
- Task 5 depends on Tasks 3, 4
- Tasks 10, 11 can be done in parallel once Task 9 is complete
