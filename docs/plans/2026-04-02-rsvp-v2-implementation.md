# RSVP v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the SpeedRead iOS RSVP reader with hyphen-aware tokenization, stable fixed-zone layout, inline WPM controls, proportional swipe scrubbing, bookmarks, highlights, and bookshelf theming.

**Architecture:** TDD approach across 8 tasks. Data layer first (models + tokenization), then engine changes, then UI (RSVPView rewrite, new viewer sheets), then theming system. Each task is self-contained with tests, implementation, and commit.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, @Observable, Swift Testing framework, Swift Concurrency

---

### Task 1: Hyphen-Aware Word Tokenization

**Files:**
- Modify: `SpeedRead/Models/Book.swift`
- Modify: `SpeedReadTests/BookTests.swift`

**Step 1: Write the failing tests**

Add to `SpeedReadTests/BookTests.swift`:

```swift
@Test func tokenizeSplitsHyphenatedWords() {
    let tokens = Book.tokenize("self-awareness is key")
    #expect(tokens == ["self-", "awareness", "is", "key"])
}

@Test func tokenizePreservesEmDash() {
    let tokens = Book.tokenize("hello\u{2014}world")
    #expect(tokens == ["hello\u{2014}world"])
}

@Test func tokenizePreservesEnDash() {
    let tokens = Book.tokenize("pages 10\u{2013}20")
    #expect(tokens == ["pages", "10\u{2013}20"])
}

@Test func tokenizeHandlesMultipleHyphens() {
    let tokens = Book.tokenize("state-of-the-art design")
    #expect(tokens == ["state-", "of-", "the-", "art", "design"])
}

@Test func tokenizeDoesNotSplitPureHyphens() {
    let tokens = Book.tokenize("hello -- world")
    #expect(tokens == ["hello", "--", "world"])
}

@Test func tokenizeDoesNotSplitTrailingHyphen() {
    let tokens = Book.tokenize("non- stop")
    #expect(tokens == ["non-", "stop"])
}

@Test func tokenizeDoesNotSplitLeadingHyphen() {
    let tokens = Book.tokenize("-prefix word")
    #expect(tokens == ["-prefix", "word"])
}

@Test func wordCountMatchesTokenizedWords() {
    let book = Book(
        title: "T", author: "A",
        extractedText: "self-awareness is well-known",
        sourceFileName: "t.epub"
    )
    #expect(book.wordCount == 4) // self- awareness is well- known → 5? No: self- awareness is well- known = 5
}
```

Wait — let me recount: `"self-awareness is well-known"` → `["self-", "awareness", "is", "well-", "known"]` = 5 words.

```swift
@Test func wordCountMatchesTokenizedWords() {
    let book = Book(
        title: "T", author: "A",
        extractedText: "self-awareness is well-known",
        sourceFileName: "t.epub"
    )
    #expect(book.wordCount == 5)
    #expect(book.words.count == 5)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/BookTests 2>&1 | tail -20`
Expected: FAIL — `Book.tokenize` does not exist

**Step 3: Implement tokenization**

In `SpeedRead/Models/Book.swift`, add the static tokenizer and update `words` and `init`:

```swift
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
    var wordCount: Int

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
        self.wordCount = Book.tokenize(extractedText).count
    }

    var words: [String] {
        Book.tokenize(extractedText)
    }

    var progress: Double {
        guard wordCount > 0 else { return 0.0 }
        return Double(lastReadWordIndex) / Double(wordCount)
    }

    /// Splits text into RSVP-ready tokens.
    /// Hyphenated words like "self-awareness" become ["self-", "awareness"].
    /// Em-dashes and en-dashes are preserved (not split).
    static func tokenize(_ text: String) -> [String] {
        let rawWords = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var result: [String] = []
        for word in rawWords {
            result.append(contentsOf: splitHyphens(word))
        }
        return result
    }

    private static func splitHyphens(_ word: String) -> [String] {
        // Don't split em-dashes or en-dashes
        // Don't split if the word is just hyphens/punctuation
        guard word.contains("-") else { return [word] }

        // Split on ASCII hyphen only
        let parts = word.split(separator: "-", omittingEmptySubsequences: false)

        // If only one part (no actual hyphen split happened), return as-is
        guard parts.count > 1 else { return [word] }

        var tokens: [String] = []
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let partStr = String(part)

            // Skip empty parts from leading/trailing/double hyphens
            if partStr.isEmpty {
                // If this creates a leading hyphen situation, accumulate
                if !tokens.isEmpty {
                    // Append hyphen to previous token
                    tokens[tokens.count - 1] += "-"
                } else {
                    tokens.append("-")
                }
                continue
            }

            let hasLetters = partStr.contains(where: { $0.isLetter })

            if !isLast && hasLetters {
                // Not the last part and has letters: attach hyphen and emit
                tokens.append(partStr + "-")
            } else if isLast && hasLetters {
                // Last part with letters: standalone word
                // But check if previous token exists and has no letters — merge
                tokens.append(partStr)
            } else {
                // No letters (pure numbers or punctuation) — don't split
                if tokens.isEmpty {
                    tokens.append(partStr + (isLast ? "" : "-"))
                } else {
                    tokens[tokens.count - 1] += partStr + (isLast ? "" : "-")
                }
            }
        }

        // If splitting produced only one token, return original
        if tokens.count <= 1 { return [word] }

        return tokens
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/BookTests 2>&1 | tail -20`
Expected: ALL PASS

**Step 5: Update existing BookTests that expect old word counts**

The existing test `wordsPropertySplitsText` uses `"Hello world this is a test"` (no hyphens) — should still pass unchanged. Verify all existing BookTests still pass.

**Step 6: Commit**

```bash
git add SpeedRead/Models/Book.swift SpeedReadTests/BookTests.swift
git commit -m "feat: hyphen-aware word tokenization for RSVP reader

Splits hyphenated words like 'self-awareness' into ['self-', 'awareness']
while preserving em-dashes and en-dashes as punctuation pauses."
```

---

### Task 2: Raise WPM Cap to 1500

**Files:**
- Modify: `SpeedRead/Engine/RSVPEngine.swift:22-23`
- Modify: `SpeedReadTests/RSVPEngineTests.swift`

**Step 1: Update the failing test**

In `SpeedReadTests/RSVPEngineTests.swift`, update the existing clamp test:

```swift
@Test @MainActor func wpmClampedToRange() {
    let engine = RSVPEngine()
    engine.wpm = 50
    #expect(engine.wpm == 100)
    engine.wpm = 2000
    #expect(engine.wpm == 1500)
}

@Test @MainActor func wpm1500IsValid() {
    let engine = RSVPEngine()
    engine.wpm = 1500
    #expect(engine.wpm == 1500)
}
```

**Step 2: Run tests to verify the clamp test fails**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/RSVPEngineTests 2>&1 | tail -20`
Expected: `wpmClampedToRange` FAILS (expects 1500 but gets 1000)

**Step 3: Update WPM clamp**

In `SpeedRead/Engine/RSVPEngine.swift`, change line 23:

```swift
var wpm: Int {
    get { _wpm }
    set {
        _wpm = max(100, min(1500, newValue))
        timer.wpm = _wpm
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/RSVPEngineTests 2>&1 | tail -20`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add SpeedRead/Engine/RSVPEngine.swift SpeedReadTests/RSVPEngineTests.swift
git commit -m "feat: raise maximum WPM from 1000 to 1500"
```

---

### Task 3: Bookmark & Highlight SwiftData Models

**Files:**
- Create: `SpeedRead/Models/Bookmark.swift`
- Create: `SpeedRead/Models/Highlight.swift`
- Modify: `SpeedRead/Models/Book.swift` (add relationships)
- Modify: `SpeedRead/SpeedReadApp.swift` (register models)
- Create: `SpeedReadTests/BookmarkTests.swift`
- Create: `SpeedReadTests/HighlightTests.swift`

**Step 1: Write failing tests for Bookmark**

Create `SpeedReadTests/BookmarkTests.swift`:

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("Bookmark Model Tests")
struct BookmarkTests {
    @Test func bookmarkInitializesCorrectly() {
        let bookmark = Bookmark(wordIndex: 42, previewText: "the quick brown fox jumped")
        #expect(bookmark.wordIndex == 42)
        #expect(bookmark.previewText == "the quick brown fox jumped")
        #expect(bookmark.book == nil)
    }

    @Test func bookmarkPreviewTextGeneration() {
        let words = ["Once", "upon", "a", "time", "in", "a", "land", "far", "away", "there"]
        let preview = Bookmark.previewText(from: words, at: 4, windowSize: 5)
        #expect(preview == "upon a time in a")
    }

    @Test func bookmarkPreviewAtStart() {
        let words = ["Once", "upon", "a", "time", "in"]
        let preview = Bookmark.previewText(from: words, at: 0, windowSize: 5)
        #expect(preview == "Once upon a time in")
    }

    @Test func bookmarkPreviewAtEnd() {
        let words = ["Once", "upon", "a", "time", "in"]
        let preview = Bookmark.previewText(from: words, at: 4, windowSize: 5)
        #expect(preview == "upon a time in")
    }
}
```

**Step 2: Write failing tests for Highlight**

Create `SpeedReadTests/HighlightTests.swift`:

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("Highlight Model Tests")
struct HighlightTests {
    @Test func highlightInitializesCorrectly() {
        let highlight = Highlight(
            startWordIndex: 10,
            endWordIndex: 25,
            highlightedText: "the quick brown fox"
        )
        #expect(highlight.startWordIndex == 10)
        #expect(highlight.endWordIndex == 25)
        #expect(highlight.highlightedText == "the quick brown fox")
        #expect(highlight.book == nil)
    }

    @Test func highlightTextCapture() {
        let words = ["Once", "upon", "a", "time", "in", "a", "land"]
        let text = Highlight.captureText(from: words, start: 1, end: 4)
        #expect(text == "upon a time in")
    }

    @Test func highlightWordCount() {
        let highlight = Highlight(
            startWordIndex: 10,
            endWordIndex: 25,
            highlightedText: "some text"
        )
        #expect(highlight.wordSpan == 16)
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/BookmarkTests -only-testing:SpeedReadTests/HighlightTests 2>&1 | tail -20`
Expected: FAIL — models don't exist

**Step 4: Implement Bookmark model**

Create `SpeedRead/Models/Bookmark.swift`:

```swift
//  Bookmark.swift
import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID
    var wordIndex: Int
    var previewText: String
    var createdAt: Date
    var book: Book?

    init(wordIndex: Int, previewText: String) {
        self.id = UUID()
        self.wordIndex = wordIndex
        self.previewText = previewText
        self.createdAt = Date()
    }

    /// Generates preview text: up to `windowSize` words centered on `index`.
    static func previewText(from words: [String], at index: Int, windowSize: Int = 5) -> String {
        guard !words.isEmpty else { return "" }
        let half = windowSize / 2
        let start = max(0, index - half)
        let end = min(words.count, start + windowSize)
        return words[start..<end].joined(separator: " ")
    }
}
```

**Step 5: Implement Highlight model**

Create `SpeedRead/Models/Highlight.swift`:

```swift
//  Highlight.swift
import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var startWordIndex: Int
    var endWordIndex: Int
    var highlightedText: String
    var createdAt: Date
    var book: Book?

    init(startWordIndex: Int, endWordIndex: Int, highlightedText: String) {
        self.id = UUID()
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
        self.highlightedText = highlightedText
        self.createdAt = Date()
    }

    /// Number of words in this highlight (inclusive range).
    var wordSpan: Int {
        endWordIndex - startWordIndex + 1
    }

    /// Captures the text between start and end indices from a word array.
    static func captureText(from words: [String], start: Int, end: Int) -> String {
        guard start >= 0, end < words.count, start <= end else { return "" }
        return words[start...end].joined(separator: " ")
    }
}
```

**Step 6: Add relationships to Book model**

In `SpeedRead/Models/Book.swift`, add inside the class body:

```swift
@Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
var bookmarks: [Bookmark] = []

@Relationship(deleteRule: .cascade, inverse: \Highlight.book)
var highlights: [Highlight] = []
```

**Step 7: Register models in SwiftData container**

In `SpeedRead/SpeedReadApp.swift`, update the model container:

```swift
.modelContainer(for: [Book.self, Bookmark.self, Highlight.self])
```

**Step 8: Run tests to verify they pass**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/BookmarkTests -only-testing:SpeedReadTests/HighlightTests 2>&1 | tail -20`
Expected: ALL PASS

**Step 9: Run ALL tests to verify no regressions**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: ALL PASS

**Step 10: Commit**

```bash
git add SpeedRead/Models/Bookmark.swift SpeedRead/Models/Highlight.swift SpeedRead/Models/Book.swift SpeedRead/SpeedReadApp.swift SpeedReadTests/BookmarkTests.swift SpeedReadTests/HighlightTests.swift
git commit -m "feat: add Bookmark and Highlight SwiftData models

Book-scoped models with cascade delete. Bookmark stores word position +
preview text. Highlight captures start/end word range + full text."
```

---

### Task 4: Theme Manager & Shelf Themes

**Files:**
- Create: `SpeedRead/Theme/ShelfTheme.swift`
- Create: `SpeedRead/Theme/ThemeManager.swift`
- Modify: `SpeedRead/Theme/SpineColor.swift`
- Create: `SpeedReadTests/ThemeTests.swift`

**Step 1: Write failing tests**

Create `SpeedReadTests/ThemeTests.swift`:

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("Theme Manager Tests")
struct ThemeTests {
    @Test func allThemesHaveUniqueIds() {
        let ids = ShelfTheme.allThemes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func classicThemeIsDefault() {
        let manager = ThemeManager()
        #expect(manager.currentTheme.id == "classic")
    }

    @Test func canSwitchTheme() {
        let manager = ThemeManager()
        manager.selectedThemeId = "midnight"
        #expect(manager.currentTheme.id == "midnight")
        #expect(manager.currentTheme.name == "Midnight Library")
    }

    @Test func invalidThemeIdFallsBackToClassic() {
        let manager = ThemeManager()
        manager.selectedThemeId = "nonexistent"
        #expect(manager.currentTheme.id == "classic")
    }

    @Test func allThemesHaveSpineColors() {
        for theme in ShelfTheme.allThemes {
            #expect(!theme.spineColors.isEmpty, "Theme \(theme.name) has no spine colors")
        }
    }

    @Test func spineColorWithPaletteIsDeterministic() {
        let palette = ShelfTheme.classic.spineColors
        let color1 = SpineColor.color(for: "Test Book", from: palette)
        let color2 = SpineColor.color(for: "Test Book", from: palette)
        #expect(color1 == color2)
    }

    @Test func fourThemesShipped() {
        #expect(ShelfTheme.allThemes.count == 4)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/ThemeTests 2>&1 | tail -20`
Expected: FAIL — ShelfTheme and ThemeManager don't exist

**Step 3: Implement ShelfTheme**

Create `SpeedRead/Theme/ShelfTheme.swift`:

```swift
//  ShelfTheme.swift
import SwiftUI

struct ShelfTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let spineColors: [Color]
    let spineTextColor: Color
    let shelfColor: Color
    let shelfHighlightColor: Color
    let backgroundColor: Color
    let fontDesign: Font.Design

    static let allThemes: [ShelfTheme] = [classic, midnight, modern, vintage]

    // MARK: - Classic (current warm walnut look)
    static let classic = ShelfTheme(
        id: "classic",
        name: "Classic",
        spineColors: [
            Color(red: 0x00/255, green: 0x5F/255, blue: 0x73/255), // deep teal
            Color(red: 0x7B/255, green: 0x2D/255, blue: 0x26/255), // burgundy
            Color(red: 0x2D/255, green: 0x4A/255, blue: 0x22/255), // forest green
            Color(red: 0x1B/255, green: 0x2A/255, blue: 0x4A/255), // navy
            Color(red: 0x8B/255, green: 0x4A/255, blue: 0x2B/255), // burnt sienna
            Color(red: 0x5B/255, green: 0x2C/255, blue: 0x5E/255), // plum
            Color(red: 0x4A/255, green: 0x5A/255, blue: 0x6A/255), // slate blue
            Color(red: 0x8B/255, green: 0x73/255, blue: 0x2A/255), // ochre
            Color(red: 0x3E/255, green: 0x27/255, blue: 0x23/255), // walnut
            Color(red: 0x6B/255, green: 0x3A/255, blue: 0x2A/255), // leather brown
        ],
        spineTextColor: Color.parchment,
        shelfColor: Color.walnut,
        shelfHighlightColor: Color.lamplight,
        backgroundColor: Color.parchment,
        fontDesign: .serif
    )

    // MARK: - Midnight Library
    static let midnight = ShelfTheme(
        id: "midnight",
        name: "Midnight Library",
        spineColors: [
            Color(red: 0x1A/255, green: 0x3C/255, blue: 0x5E/255), // deep sapphire
            Color(red: 0x5C/255, green: 0x1A/255, blue: 0x3B/255), // garnet
            Color(red: 0x1A/255, green: 0x4D/255, blue: 0x3E/255), // emerald dark
            Color(red: 0x3D/255, green: 0x1A/255, blue: 0x5C/255), // amethyst
            Color(red: 0x5C/255, green: 0x3D/255, blue: 0x1A/255), // bronze
            Color(red: 0x1A/255, green: 0x1A/255, blue: 0x4D/255), // midnight blue
            Color(red: 0x4D/255, green: 0x1A/255, blue: 0x1A/255), // deep crimson
            Color(red: 0x2E/255, green: 0x4A/255, blue: 0x5A/255), // steel teal
            Color(red: 0x3A/255, green: 0x2A/255, blue: 0x4A/255), // twilight purple
            Color(red: 0x4A/255, green: 0x3A/255, blue: 0x2A/255), // dark umber
        ],
        spineTextColor: Color(red: 0xD4/255, green: 0xD0/255, blue: 0xC8/255),
        shelfColor: Color(red: 0x2A/255, green: 0x1E/255, blue: 0x1A/255),
        shelfHighlightColor: Color(red: 0x4A/255, green: 0x4A/255, blue: 0x6A/255),
        backgroundColor: Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255),
        fontDesign: .serif
    )

    // MARK: - Modern Minimal
    static let modern = ShelfTheme(
        id: "modern",
        name: "Modern Minimal",
        spineColors: [
            Color(red: 0xB8/255, green: 0xC4/255, blue: 0xCA/255), // cool gray
            Color(red: 0xD4/255, green: 0xA5/255, blue: 0xA5/255), // dusty rose
            Color(red: 0xA5/255, green: 0xC4/255, blue: 0xB8/255), // sage
            Color(red: 0xC4/255, green: 0xB8/255, blue: 0xA5/255), // warm sand
            Color(red: 0xA5/255, green: 0xA5/255, blue: 0xC4/255), // lavender gray
            Color(red: 0xC4/255, green: 0xC4/255, blue: 0xB8/255), // stone
            Color(red: 0xB8/255, green: 0xA5/255, blue: 0xC4/255), // mauve
            Color(red: 0xA5/255, green: 0xB8/255, blue: 0xB8/255), // seafoam
            Color(red: 0xD4/255, green: 0xC4/255, blue: 0xA5/255), // champagne
            Color(red: 0xC4/255, green: 0xA5/255, blue: 0xB8/255), // blush
        ],
        spineTextColor: Color(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255),
        shelfColor: Color(red: 0xE8/255, green: 0xE4/255, blue: 0xE0/255),
        shelfHighlightColor: .white,
        backgroundColor: Color(red: 0xF8/255, green: 0xF6/255, blue: 0xF4/255),
        fontDesign: .default
    )

    // MARK: - Vintage
    static let vintage = ShelfTheme(
        id: "vintage",
        name: "Vintage",
        spineColors: [
            Color(red: 0x8B/255, green: 0x73/255, blue: 0x55/255), // aged ochre
            Color(red: 0x6B/255, green: 0x7B/255, blue: 0x5B/255), // olive
            Color(red: 0x8B/255, green: 0x5B/255, blue: 0x4B/255), // terracotta
            Color(red: 0x5B/255, green: 0x6B/255, blue: 0x7B/255), // faded denim
            Color(red: 0x7B/255, green: 0x5B/255, blue: 0x6B/255), // muted plum
            Color(red: 0x6B/255, green: 0x6B/255, blue: 0x5B/255), // sage brown
            Color(red: 0x8B/255, green: 0x6B/255, blue: 0x5B/255), // sienna light
            Color(red: 0x5B/255, green: 0x7B/255, blue: 0x6B/255), // patina green
            Color(red: 0x7B/255, green: 0x6B/255, blue: 0x5B/255), // worn leather
            Color(red: 0x6B/255, green: 0x5B/255, blue: 0x5B/255), // faded mahogany
        ],
        spineTextColor: Color(red: 0xF5/255, green: 0xEB/255, blue: 0xD5/255),
        shelfColor: Color(red: 0x5D/255, green: 0x47/255, blue: 0x37/255),
        shelfHighlightColor: Color(red: 0xD4/255, green: 0xC0/255, blue: 0x90/255),
        backgroundColor: Color(red: 0xF5/255, green: 0xE6/255, blue: 0xC8/255),
        fontDesign: .serif
    )
}
```

**Step 4: Implement ThemeManager**

Create `SpeedRead/Theme/ThemeManager.swift`:

```swift
//  ThemeManager.swift
import SwiftUI
import Observation

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var selectedThemeId: String {
        didSet {
            UserDefaults.standard.set(selectedThemeId, forKey: "selectedThemeId")
        }
    }

    var currentTheme: ShelfTheme {
        ShelfTheme.allThemes.first { $0.id == selectedThemeId } ?? .classic
    }

    init() {
        self.selectedThemeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "classic"
    }
}
```

**Step 5: Update SpineColor to accept custom palettes**

In `SpeedRead/Theme/SpineColor.swift`, add an overload:

```swift
static func color(for title: String, from palette: [Color]) -> Color {
    guard !palette.isEmpty else { return spineColors[colorIndex(for: title)] }
    let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
    return palette[abs(hash) % palette.count]
}
```

**Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SpeedReadTests/ThemeTests 2>&1 | tail -20`
Expected: ALL PASS

**Step 7: Run all tests for regressions**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: ALL PASS

**Step 8: Commit**

```bash
git add SpeedRead/Theme/ShelfTheme.swift SpeedRead/Theme/ThemeManager.swift SpeedRead/Theme/SpineColor.swift SpeedReadTests/ThemeTests.swift
git commit -m "feat: add theme manager with 4 bookshelf themes

Classic, Midnight Library, Modern Minimal, and Vintage themes.
ThemeManager persists selection via UserDefaults."
```

---

### Task 5: RSVPView Rewrite — Fixed 3-Zone Layout with Inline Controls

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift` (full rewrite)

**Step 1: Rewrite RSVPView**

Replace the entire contents of `SpeedRead/Views/RSVPView.swift`:

```swift
//  RSVPView.swift
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var engine = RSVPEngine()
    @State private var highlightStartIndex: Int?
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var bookmarkFlash = false
    @State private var highlightFlash = false

    // Scrub gesture state
    @State private var lastDragX: CGFloat = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var lastDragTime: Date = .now
    @State private var dragVelocity: CGFloat = 0

    private let basePtsPerWord: CGFloat = 8
    private let maxVelocityMultiplier: CGFloat = 50
    private let hapticInterval = 10

    var body: some View {
        ZStack {
            // Warm dark background with vignette
            Color.rsvpBackground
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        center: .center,
                        startRadius: 200,
                        endRadius: 500
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                // ─── ZONE 1: Top Bar ───
                topBar
                    .padding()

                // ─── ZONE 2: Word Display (fixed center) ───
                Spacer(minLength: 0)

                RSVPWordView(segments: engine.currentSegments, fontSize: 36)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.togglePlayPause()
                    }
                    .gesture(scrubGesture)

                Spacer(minLength: 0)

                // ─── ZONE 3: Control Panel (fixed height) ───
                controlPanel
                    .frame(height: 160)
                    .padding(.bottom, 20)
            }

            // Bookmark flash overlay
            if bookmarkFlash {
                Color.agedGold.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Highlight flash overlay
            if highlightFlash {
                Color.crimson.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.load(words: book.words, startingAt: book.lastReadWordIndex)
        }
        .onDisappear {
            book.lastReadWordIndex = engine.currentIndex
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListView(book: book, engine: engine)
        }
        .sheet(isPresented: $showHighlights) {
            HighlightListView(book: book, engine: engine)
        }
    }

    // MARK: - Zone 1: Top Bar

    private var topBar: some View {
        HStack {
            Button {
                book.lastReadWordIndex = engine.currentIndex
                engine.stop()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("Close")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.rsvpText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.walnut.opacity(0.6), in: Capsule())
            }
            .frame(minWidth: 44, minHeight: 44)

            Spacer()

            Text(book.title)
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(Color.rsvpText.opacity(0.4))
                .lineLimit(1)

            Spacer()

            // Settings menu
            Menu {
                Button {
                    showBookmarks = true
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                Button {
                    showHighlights = true
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.rsvpText)
                    .padding(10)
                    .background(Color.walnut.opacity(0.6), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    // MARK: - Zone 3: Control Panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            // WPM Controls — always visible, works while playing
            wpmControls

            // Action buttons — visible when paused, invisible (but space-holding) when playing
            actionButtons
                .opacity(engine.state != .playing ? 1 : 0)

            // Progress bar + word counter — always visible
            progressSection
        }
        .padding(.horizontal)
    }

    private var wpmControls: some View {
        HStack(spacing: 20) {
            Button {
                engine.wpm -= 25
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.walnut.opacity(0.8))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Decrease speed by 25 words per minute")

            Text("\(engine.wpm) WPM")
                .font(.numeric(size: 18, weight: .medium))
                .foregroundStyle(Color.agedGold)
                .frame(minWidth: 100)
                .accessibilityLabel("\(engine.wpm) words per minute")

            Button {
                engine.wpm += 25
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.walnut.opacity(0.8))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Increase speed by 25 words per minute")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Play button
            Button {
                engine.play()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.crimsonSoft)
            }
            .frame(minWidth: 44, minHeight: 44)

            // Bookmark button
            Button {
                addBookmark()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.agedGold)
                    .padding(10)
                    .background(Color.walnut.opacity(0.6), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)

            // Highlight button
            Button {
                toggleHighlight()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: highlightStartIndex != nil ? "highlighter" : "highlighter")
                    Text(highlightStartIndex != nil ? "Stop" : "Highlight")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(highlightStartIndex != nil ? .white : Color.rsvpText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    highlightStartIndex != nil ? Color.crimson : Color.walnut.opacity(0.6),
                    in: Capsule()
                )
            }
            .frame(minHeight: 44)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.walnut)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.agedGold.opacity(0.7), Color.agedGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * engine.progress, height: 4)
                        .animation(.linear(duration: 0.1), value: engine.progress)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Word \(engine.currentIndex + 1)")
                Spacer()
                Text("of \(engine.totalWords)")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.rsvpText.opacity(0.4))
            .monospacedDigit()
        }
    }

    // MARK: - Scrub Gesture

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard engine.state != .playing else { return }

                let now = Date.now
                let deltaX = value.translation.width - lastDragX
                let deltaTime = now.timeIntervalSince(lastDragTime)

                // Calculate velocity (points per second)
                if deltaTime > 0 {
                    dragVelocity = abs(deltaX / CGFloat(deltaTime))
                }

                // Velocity-based multiplier: faster swipes cover more ground
                let velocityFactor = min(dragVelocity / 500, maxVelocityMultiplier / basePtsPerWord)
                let effectivePtsPerWord = basePtsPerWord / max(1, velocityFactor)

                dragAccumulator += deltaX
                let wordDelta = Int(dragAccumulator / effectivePtsPerWord)

                if wordDelta != 0 {
                    let newIndex = engine.currentIndex + wordDelta
                    engine.seek(to: newIndex)
                    dragAccumulator -= CGFloat(wordDelta) * effectivePtsPerWord

                    // Haptic every N words
                    if abs(wordDelta) >= hapticInterval || engine.currentIndex % hapticInterval == 0 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                lastDragX = value.translation.width
                lastDragTime = now
            }
            .onEnded { _ in
                lastDragX = 0
                dragAccumulator = 0
                dragVelocity = 0
            }
    }

    // MARK: - Actions

    private func addBookmark() {
        let preview = Bookmark.previewText(from: book.words, at: engine.currentIndex)
        let bookmark = Bookmark(wordIndex: engine.currentIndex, previewText: preview)
        bookmark.book = book
        modelContext.insert(bookmark)

        withAnimation(.easeOut(duration: 0.3)) { bookmarkFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.2)) { bookmarkFlash = false }
        }
    }

    private func toggleHighlight() {
        if let startIndex = highlightStartIndex {
            // Stop highlighting
            let endIndex = engine.currentIndex
            let actualStart = min(startIndex, endIndex)
            let actualEnd = max(startIndex, endIndex)
            let text = Highlight.captureText(from: book.words, start: actualStart, end: actualEnd)
            let highlight = Highlight(startWordIndex: actualStart, endWordIndex: actualEnd, highlightedText: text)
            highlight.book = book
            modelContext.insert(highlight)
            highlightStartIndex = nil

            withAnimation(.easeOut(duration: 0.3)) { highlightFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.2)) { highlightFlash = false }
            }
        } else {
            // Start highlighting
            highlightStartIndex = engine.currentIndex
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED (this is a UI file — visual testing needed, but compilation must pass)

**Step 3: Run all tests for regressions**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "feat: rewrite RSVPView with fixed 3-zone layout

- Fixed center word display that never shifts vertically
- Inline WPM +/- controls (25 increments, works while playing)
- Close button always visible in top bar
- Proportional swipe-to-scrub when paused (velocity-based)
- Bookmark and highlight buttons in control panel
- Removed WPM settings sheet"
```

---

### Task 6: Bookmark List View

**Files:**
- Create: `SpeedRead/Views/BookmarkListView.swift`

**Step 1: Implement BookmarkListView**

Create `SpeedRead/Views/BookmarkListView.swift`:

```swift
//  BookmarkListView.swift
import SwiftUI
import SwiftData

struct BookmarkListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sortedBookmarks: [Bookmark] {
        book.bookmarks.sorted { $0.wordIndex < $1.wordIndex }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                if sortedBookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                        Text("No bookmarks yet")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.rsvpText.opacity(0.5))
                        Text("Tap the bookmark icon while paused to save your place")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(sortedBookmarks) { bookmark in
                            Button {
                                engine.seek(to: bookmark.wordIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Word \(bookmark.wordIndex + 1)")
                                        .font(.numeric(size: 13, weight: .medium))
                                        .foregroundStyle(Color.agedGold)
                                    Text(bookmark.previewText)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.rsvpText.opacity(0.7))
                                        .lineLimit(2)
                                    Text(bookmark.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.rsvpText.opacity(0.3))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.walnut.opacity(0.3))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(sortedBookmarks[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/BookmarkListView.swift
git commit -m "feat: add bookmark list view with seek navigation"
```

---

### Task 7: Highlight List View

**Files:**
- Create: `SpeedRead/Views/HighlightListView.swift`

**Step 1: Implement HighlightListView**

Create `SpeedRead/Views/HighlightListView.swift`:

```swift
//  HighlightListView.swift
import SwiftUI
import SwiftData

struct HighlightListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sortedHighlights: [Highlight] {
        book.highlights.sorted { $0.startWordIndex < $1.startWordIndex }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                if sortedHighlights.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                        Text("No highlights yet")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.rsvpText.opacity(0.5))
                        Text("Tap Highlight while paused, read or scrub, then tap Stop")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(sortedHighlights) { highlight in
                            Button {
                                engine.seek(to: highlight.startWordIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Words \(highlight.startWordIndex + 1)–\(highlight.endWordIndex + 1)")
                                            .font(.numeric(size: 13, weight: .medium))
                                            .foregroundStyle(Color.agedGold)
                                        Spacer()
                                        Text("\(highlight.wordSpan) words")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                                    }
                                    Text(highlight.highlightedText)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.rsvpText.opacity(0.7))
                                        .lineLimit(3)
                                    Text(highlight.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.rsvpText.opacity(0.3))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.walnut.opacity(0.3))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(sortedHighlights[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/HighlightListView.swift
git commit -m "feat: add highlight list view with seek navigation"
```

---

### Task 8: Theme Picker View & Library Integration

**Files:**
- Create: `SpeedRead/Views/ThemePickerView.swift`
- Modify: `SpeedRead/Views/BookSpineView.swift`
- Modify: `SpeedRead/Views/BookshelfRowView.swift`
- Modify: `SpeedRead/Views/LibraryView.swift`
- Modify: `SpeedRead/SpeedReadApp.swift`

**Step 1: Create ThemePickerView**

Create `SpeedRead/Views/ThemePickerView.swift`:

```swift
//  ThemePickerView.swift
import SwiftUI

struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(ShelfTheme.allThemes) { theme in
                            themeCard(theme)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func themeCard(_ theme: ShelfTheme) -> some View {
        @Bindable var tm = themeManager
        let isSelected = tm.selectedThemeId == theme.id

        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                tm.selectedThemeId = theme.id
            }
        } label: {
            VStack(spacing: 8) {
                // Mini shelf preview
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.spineColors[i % theme.spineColors.count])
                            .frame(width: 24, height: CGFloat.random(in: 40...60))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Shelf line
                Rectangle()
                    .fill(theme.shelfColor)
                    .frame(height: 6)

                Text(theme.name)
                    .font(.system(size: 15, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.spineTextColor)
                    .padding(.bottom, 12)
            }
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.agedGold : .clear, lineWidth: 2)
            )
        }
    }
}
```

**Step 2: Update BookSpineView to use theme**

Replace `SpeedRead/Views/BookSpineView.swift`:

```swift
//  BookSpineView.swift
import SwiftUI

struct BookSpineView: View {
    let title: String
    let author: String
    let progress: Double
    let wordCount: Int

    @Environment(ThemeManager.self) private var themeManager

    private var spineHeight: CGFloat {
        let base: CGFloat = 120
        let extra = min(CGFloat(wordCount) / 50_000.0, 1.0) * 60
        return base + extra
    }

    private var spineColor: Color {
        SpineColor.color(for: title, from: themeManager.currentTheme.spineColors)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(spineColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.15))
                        .frame(width: 2)
                        .padding(.vertical, 8),
                    alignment: .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)

            VStack(spacing: 4) {
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.spineTextColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(author)
                    .font(.system(size: 7, weight: .regular, design: theme.fontDesign))
                    .foregroundStyle(theme.spineTextColor.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.agedGold)
                        .frame(width: geo.size.width, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(0.8)
                }
            }
        }
        .frame(width: 60, height: spineHeight)
    }
}

#Preview {
    HStack(spacing: 8) {
        BookSpineView(title: "Alice in Wonderland", author: "Lewis Carroll", progress: 0.4, wordCount: 27000)
        BookSpineView(title: "The Metamorphosis", author: "Franz Kafka", progress: 0, wordCount: 15000)
        BookSpineView(title: "A Christmas Carol", author: "Charles Dickens", progress: 0.8, wordCount: 30000)
    }
    .padding()
    .background(Color.walnut)
    .environment(ThemeManager())
}
```

**Step 3: Update BookshelfRowView to use theme**

Replace `SpeedRead/Views/BookshelfRowView.swift`:

```swift
//  BookshelfRowView.swift
import SwiftUI

struct BookshelfRowView<Content: View>: View {
    let content: Content

    @Environment(ThemeManager.self) private var themeManager

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                content
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 0)

            shelfPlank
        }
    }

    private var shelfPlank: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.shelfColor.opacity(0.8),
                            theme.shelfColor,
                            theme.shelfColor.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 12)

            Rectangle()
                .fill(theme.shelfHighlightColor.opacity(0.15))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 12)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

#Preview {
    ScrollView {
        BookshelfRowView {
            BookSpineView(title: "Alice", author: "Carroll", progress: 0.5, wordCount: 27000)
            BookSpineView(title: "Kafka", author: "Kafka", progress: 0, wordCount: 15000)
        }
    }
    .background(Color.parchment)
    .environment(ThemeManager())
}
```

**Step 4: Update LibraryView with theme picker and themed background**

In `SpeedRead/Views/LibraryView.swift`, make these changes:

1. Add `@Environment(ThemeManager.self) private var themeManager`
2. Add `@State private var showThemePicker = false`
3. Replace `Color.parchment.ignoresSafeArea()` with `themeManager.currentTheme.backgroundColor.ignoresSafeArea()`
4. Replace `.toolbarBackground(Color.parchment, ...)` with `.toolbarBackground(themeManager.currentTheme.backgroundColor, ...)`
5. Add theme picker toolbar button
6. Add `.sheet(isPresented: $showThemePicker) { ThemePickerView() }`

Full updated LibraryView:

```swift
//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject var syncService: WatchSyncService
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var showThemePicker = false
    @State private var importError: String?
    @State private var showError = false

    private let booksPerShelf = 4

    private var shelves: [[Book]] {
        stride(from: 0, to: books.count, by: booksPerShelf).map {
            Array(books[$0..<min($0 + booksPerShelf, books.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()

                if books.isEmpty {
                    emptyLibraryView
                } else {
                    bookshelfView
                }
            }
            .navigationTitle("Your Library")
            .toolbarBackground(themeManager.currentTheme.backgroundColor, for: .navigationBar)
            .task {
                SampleBookLoader(modelContext: modelContext).loadSampleBooksIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showThemePicker = true
                        } label: {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(Color.crimsonSoft)
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.crimsonSoft)
                        }
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
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .overlay(alignment: .bottom) {
                if case .sending(let title) = syncService.sendState {
                    SendToast(icon: "arrow.up.circle", message: "Sending \(title)...", color: Color.agedGold)
                } else if case .sent(let title) = syncService.sendState {
                    SendToast(icon: "checkmark.circle.fill", message: "Sent \(title) to Watch", color: Color.agedGold)
                } else if case .failed(let error) = syncService.sendState {
                    SendToast(icon: "exclamationmark.triangle.fill", message: error, color: Color.crimsonSoft)
                }
            }
            .animation(.easeInOut, value: syncService.sendState != .idle)
            .sheet(isPresented: $showThemePicker) {
                ThemePickerView()
            }
        }
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            BookshelfRowView { }
            BookshelfRowView { }

            Text("Your shelves are waiting...")
                .font(.displayFont(size: 20, weight: .regular))
                .italic()
                .foregroundStyle(Color.walnutLight)
                .padding(.top, 20)

            Button {
                showImporter = true
            } label: {
                Label("Import a Book", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.parchment)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.crimsonSoft, in: Capsule())
            }
        }
        .padding()
    }

    private var bookshelfView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelfBooks in
                    BookshelfRowView {
                        ForEach(shelfBooks) { book in
                            NavigationLink(value: book) {
                                BookSpineView(
                                    title: book.title,
                                    author: book.author,
                                    progress: book.progress,
                                    wordCount: book.wordCount
                                )
                            }
                            .contextMenu {
                                Button {
                                    syncService.sendBook(title: book.title, author: book.author, text: book.extractedText)
                                } label: {
                                    Label("Send to Watch", systemImage: "applewatch")
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

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
}

private struct SendToast: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

**Step 5: Inject ThemeManager in SpeedReadApp**

In `SpeedRead/SpeedReadApp.swift`:

```swift
//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environment(themeManager)
                .onAppear { syncService.activate() }
        }
        .modelContainer(for: [Book.self, Bookmark.self, Highlight.self])
    }
}
```

**Step 6: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 7: Run all tests**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: ALL PASS (SpineColor tests may need update — see note below)

**Note:** The existing `SpineColorTests` test deterministic color output. Since we added a new overload `color(for:from:)` but didn't change the original `color(for:)`, existing tests should pass unchanged. The new `ThemeTests` covers the palette overload.

**Step 8: Commit**

```bash
git add SpeedRead/Views/ThemePickerView.swift SpeedRead/Views/BookSpineView.swift SpeedRead/Views/BookshelfRowView.swift SpeedRead/Views/LibraryView.swift SpeedRead/SpeedReadApp.swift
git commit -m "feat: integrate theme system across bookshelf UI

- ThemePickerView with visual theme previews
- BookSpineView reads colors from active theme
- BookshelfRowView shelf plank uses theme colors
- LibraryView background adapts to theme
- ThemeManager injected via .environment() from app root"
```

---

## Execution Order & Dependencies

```
Task 1 (Tokenization) ──┐
Task 2 (WPM Cap)     ──┤
Task 3 (Models)       ──┼── Task 5 (RSVPView) ── Task 6 (BookmarkList) ── Task 7 (HighlightList)
Task 4 (Themes)       ──┘                    └── Task 8 (Theme Integration)
```

Tasks 1–4 are independent and can be parallelized. Tasks 5–8 depend on 1–4 being complete.

---

## Testing Checklist

After all tasks:
- [ ] All unit tests pass (`xcodebuild test`)
- [ ] Hyphenated words display as separate tokens
- [ ] RSVP word stays fixed vertically during play/pause/WPM changes
- [ ] Close button visible at all times
- [ ] WPM +/- works while playing, increments by 25, range 100-1500
- [ ] Swipe scrubbing feels proportional with haptics
- [ ] Bookmarks can be created, viewed, and navigated to
- [ ] Highlights can be started, stopped, viewed, and navigated to
- [ ] All 4 themes selectable and visually distinct
- [ ] Theme persists across app launches
- [ ] No regressions in Watch functionality
