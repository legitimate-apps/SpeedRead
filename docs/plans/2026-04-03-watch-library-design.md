# Apple Watch Library & Style Upgrade — Design

**Date:** 2026-04-03
**Approach:** B — Rich Library with Detail Views

## Overview

Upgrade the Apple Watch app from single-book mode to a multi-book library with browsing, detail views, and bookshelf-quality styling. Books sent from iPhone append to the Watch library (no replacement, UUID deduplication).

## Architecture

```
TabView (.verticalPage)
  ├─ Page 1: NowReadingView (walnut gradient)
  │    └─ sheet: WatchRSVPView → WatchSettingsView
  └─ Page 2: WatchLibraryView (inkBlack gradient)
       └─ NavigationStack
            ├─ List of books (root)
            └─ push: WatchBookDetailView (spine-color gradient)
                 └─ "Read" → sets current, scrolls to NowReading
```

- `TabView(.verticalPage)` with two pages: Now Reading + Library
- Digital Crown scrolls between tabs
- Each tab declares `containerBackground` with gradient

## Data Model

```swift
struct WatchBook: Codable, Identifiable, Hashable {
    let id: UUID           // matches iPhone Book.id for deduplication
    let title: String
    let author: String
    let text: String
    var lastReadIndex: Int
    var lastReadDate: Date?
    let wordCount: Int
    let dateAdded: Date
}

struct WatchLibrary: Codable {
    var books: [WatchBook]
    var currentBookId: UUID?
}
```

- Single file: `watchlibrary.json` in documents directory
- Migration from `watchbook.json` on first launch
- Sorted by `dateAdded` descending

## WatchSyncService Changes

**iPhone side:**
- `sendBook` now includes the book's `UUID` in the message

**Watch side (receive):**
- Extract book ID from message (generate if missing for backwards compat)
- Check library for duplicate by ID → skip if exists
- If new → append, set as current, `.success` haptic
- If duplicate → `.click` haptic, no change

**Position sync:**
- Include `bookId` in `syncReadingPosition` / `updateApplicationContext`
- Watch updates matching book's `lastReadIndex`

**Published properties refactor:**
- Replace scattered `lastReceivedBookTitle/Text/Author/Position`
- `@Published var library: WatchLibrary`
- Computed `currentBook: WatchBook?` from `library.currentBookId`
- Keep `isReceiving`/`receivingTitle` for UI state

## Watch Library List (`WatchLibraryView`)

- `NavigationStack` containing `List`
- Row layout:
  - Leading 4pt accent bar in book's spine color (Classic palette, deterministic hash)
  - Title: `.headline`, serif, `Color.parchment`, 2-line limit
  - Author: `.caption`, `Color.parchment.opacity(0.6)`, 1-line limit
  - Trailing 20pt circular progress ring in `agedGold` (if progress > 0)
  - "Now reading" book gets a `crimsonSoft` dot
- Swipe-to-delete (trailing, destructive, full swipe)
- Empty state: `books.vertical` icon + "Send books from your iPhone library"
- Navigation title: "Library" (large on root)
- Sorted by `dateAdded` descending

## Watch Book Detail (`WatchBookDetailView`)

- `containerBackground`: book's spine color gradient
- Layout (vertical):
  1. Title — `.displayFont(size: 18, weight: .semibold)`, centered
  2. Author — `.displayFont(size: 13, weight: .regular)`, centered
  3. Divider — `agedGold.opacity(0.3)`
  4. Stats row — Progress % + Word count, two columns
  5. Linear progress bar — `agedGold` on `parchment.opacity(0.15)` track
  6. "Read" / "Continue Reading" button — `crimsonSoft`, full width
  7. "Remove from Watch" — plain text, confirmation alert
- `.success` haptic on selecting book to read

## NowReadingView Updates

- Data source: `syncService.currentBook` (computed from library)
- Empty state: "Swipe up to browse your library"
- Receiving state: unchanged (spinner + title)
- RSVP: reads from `currentBook`, writes `lastReadIndex` back on close

## Design Conventions (watchOS 10+)

- `containerBackground` gradients on all tabs and pushed views
- System text styles (`.headline`, `.caption`) for Dynamic Type scaling
- Custom serif fonts (`.displayFont`) for display/branding elements
- Minimum 44pt tap targets
- Digital Crown: system handles list scrolling; custom crown kept for RSVP/settings
- OLED-friendly dark palette (walnut, inkBlack backgrounds)
- Classic theme spine colors for accent variety
