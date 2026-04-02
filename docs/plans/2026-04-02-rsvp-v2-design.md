# SpeedRead RSVP v2 — Design Document

**Date:** 2026-04-02  
**Status:** Approved  
**Scope:** iOS RSVP reader improvements + bookshelf theming

---

## 1. Hyphenated Word Tokenization

**Problem:** Hyphenated words like "self-awareness" display as one long word in the RSVP reader, making them hard to process at speed.

**Solution:** Replace naive whitespace splitting with a hyphen-aware tokenizer.

**Rules:**
- Split on hyphens (`-`) only when both sides contain at least one letter
- Hyphen stays on the first fragment: `"self-awareness"` → `["self-", "awareness"]`
- Em-dashes (`—`) and en-dashes (`–`) are NOT split — they are punctuation pauses handled by WordTimer
- Pure punctuation like `"--"` is not split
- `wordCount` recalculated using the same tokenizer

**Implementation:** `Book.swift` — new `static func tokenize(_ text: String) -> [String]` used by both `words` computed property and `init` for count.

---

## 2. Fixed 3-Zone RSVP Layout

**Problem:** Play button and controls appearing/disappearing causes vertical text jitter. WPM sheet covers the reader. No close button when paused.

**Solution:** Restructure RSVPView into a fixed 3-zone VStack:

```
┌─────────────────────────────┐
│  [Close]    Title    [⚙️]   │  Zone 1: Top Bar (always visible)
│                             │
│         s e l f -           │  Zone 2: Word Display (fixed center)
│            ▼                │    Tap to play/pause
│                             │
├─────────────────────────────┤
│  [−] 300 WPM [+]           │  Zone 3: Control Panel (fixed height)
│  [▶]  [🔖] [🖍Start]       │    Action buttons (paused only)
│  ════════════════ 45%       │    Progress bar + counter
└─────────────────────────────┘
```

**Key principles:**
- Zone 2 centered with `Spacer()` above/below — never moves
- Zone 3 has fixed frame height (~160pt). Buttons show/hide with opacity, zone height constant
- Close button always visible in top bar
- WPM +/- inline in Zone 3, increments of 25, works while playing
- No more WPM sheet

**WPM Range:** 100–1500 (up from 1000).

---

## 3. Proportional Swipe Scrubbing

**Problem:** No way to navigate through the book on iOS when paused.

**Solution:** Horizontal `DragGesture` on Zone 2 with velocity-based proportional movement.

**Mechanics:**
- Base: 1 word per 8pt of drag
- Velocity multiplier: faster swipes cover more ground (capped at ~50 words/point)
- Right = forward, left = backward
- Haptic feedback every 10 words (`UIImpactFeedbackGenerator(.light)`)
- Real-time word counter + progress bar updates
- Disabled during playback

---

## 4. Bookmarks

**SwiftData Model:**
```swift
@Model final class Bookmark {
    var id: UUID
    var wordIndex: Int
    var previewText: String   // ~5 words around bookmark
    var createdAt: Date
    var book: Book?
}
```

**Book relationship:** `@Relationship(deleteRule: .cascade) var bookmarks: [Bookmark]`

**Creating:** Bookmark button in Zone 3 action row (paused). Tap = instant save with gold flash.

**Viewing:** Sheet from gear menu or long-press bookmark button. Shows list sorted by position. Tap = seek. Swipe to delete.

---

## 5. Highlights

**SwiftData Model:**
```swift
@Model final class Highlight {
    var id: UUID
    var startWordIndex: Int
    var endWordIndex: Int
    var highlightedText: String
    var createdAt: Date
    var book: Book?
}
```

**Book relationship:** `@Relationship(deleteRule: .cascade) var highlights: [Highlight]`

**Recording:**
- "Start Highlight" button in Zone 3 (paused)
- Becomes "Stop Highlight" with red fill when active
- On stop: captures word range, joins text, saves Highlight

**Viewing:** Sheet from gear menu or long-press highlight button. Shows truncated text + word range. Tap = seek. Swipe to delete.

---

## 6. Bookshelf Theme Manager

**ShelfTheme struct:** Defines spine color palette, text color, shelf gradient, background, font design.

**Shipped themes:**

| Theme | Background | Spines | Feel |
|-------|-----------|--------|------|
| Classic | Parchment | Warm earth tones | Current look |
| Midnight Library | Dark navy | Jewel tones | Moody, rich |
| Modern Minimal | White | Pastels/neutrals | Clean, airy |
| Vintage | Aged cream | Muted ochre/olive | Antique |

**ThemeManager:** `@Observable` singleton, persisted via `@AppStorage`.

**UI:** Palette icon in LibraryView toolbar → theme picker sheet with visual previews.

**Integration:** BookSpineView, BookshelfRowView, LibraryView all read from ThemeManager.

---

## File Change Matrix

| File | Changes |
|------|---------|
| `Book.swift` | `tokenize()`, hyphen-aware `words`, Bookmark/Highlight relationships |
| `RSVPEngine.swift` | WPM clamp 100–1500 |
| `RSVPView.swift` | Full rewrite: 3-zone layout, inline WPM, scrub, bookmarks, highlights |
| `BookSpineView.swift` | Accept theme colors |
| `BookshelfRowView.swift` | Accept theme shelf colors |
| `LibraryView.swift` | Theme integration, picker button |
| `Theme.swift` | Add CodableColor helper |
| **New:** `Bookmark.swift` | SwiftData model |
| **New:** `Highlight.swift` | SwiftData model |
| **New:** `ShelfTheme.swift` | Theme definitions |
| **New:** `ThemeManager.swift` | Observable theme state |
| **New:** `BookmarkListView.swift` | Bookmark viewer |
| **New:** `HighlightListView.swift` | Highlight viewer |
| **New:** `ThemePickerView.swift` | Theme picker |
