# SpeedRead — RSVP E-Reader Design

**Date:** 2026-04-01
**Status:** Approved

## Overview

SpeedRead is an iOS + watchOS e-reader app that uses Rapid Serial Visual Presentation (RSVP) as its primary reading mode. Users import EPUB and PDF files on iPhone, read with a scrollable reader or full-screen RSVP mode, and speed-read on Apple Watch via a synced RSVP experience.

## Core Concepts

### RSVP & the Optimal Recognition Point (ORP)

RSVP displays words one at a time at a fixed screen position, eliminating saccadic eye movements (~80% of traditional reading time). The key to effective RSVP is the **Optimal Recognition Point (ORP)** — the character ~28-33% into each word where the eye naturally fixates.

Every word is positioned so its ORP character lands at the **exact same screen coordinate**. The ORP character is highlighted in red. The eye stays completely still while words change.

**ORP Lookup Table:**

| Word Length | ORP Index (0-based) |
|-------------|---------------------|
| 1           | 0                   |
| 2-5         | 1                   |
| 6-9         | 2                   |
| 10-13       | 3                   |
| 14+         | 4                   |

Leading punctuation (quotes, parentheses) is skipped — ORP is calculated from the first alphanumeric character.

### Adaptive Timing

Base delay = `60000 / WPM` milliseconds. Multipliers applied:

| Condition                      | Multiplier |
|--------------------------------|------------|
| Sentence-ending (. ? !)       | 2.0x       |
| Clause punctuation (, : ; —)  | 1.5x       |
| Long words (8+ chars)         | 1.3x       |
| Paragraph breaks              | 2.5x       |
| Numbers                       | 1.8x       |

Multipliers stack (e.g., long word ending with period = 1.3 x 2.0 = 2.6x).

### The Redicle (Display Component)

```
        ┌──────────────────────────┐
        │           ▼              │  ← top guide mark
        │   reco  g  nition        │
        │           ▲              │  ← bottom guide mark
        └──────────────────────────┘
              ↑     ↑     ↑
           left   ORP   right
          (gray)  (red)  (gray)
```

- Word split into three segments: pre-ORP (gray), ORP char (red), post-ORP (gray)
- ORP character fixed at same screen X coordinate for every word
- Guide marks (thin vertical ticks) above and below the focal point
- Font: SF Mono (monospace), bold weight
- Dark mode first (black background, white/gray text, red ORP)

## Platform Architecture

### Stack

- **UI**: Pure SwiftUI (both platforms)
- **Persistence**: SwiftData (iOS 17 / watchOS 10 minimum)
- **Sync**: WatchConnectivity framework
- **PDF parsing**: PDFKit (built-in)
- **EPUB parsing**: EPUBKit (SPM) or minimal custom parser
- **Concurrency**: Structured concurrency (async/await, Task)

### Data Model

**Book** (SwiftData @Model):
- `id: UUID`
- `title: String`
- `author: String`
- `extractedText: String` — full plain text from EPUB/PDF
- `sourceFileName: String`
- `dateAdded: Date`
- `lastReadWordIndex: Int` — reading position (0-based)
- `lastReadDate: Date?`

Computed: `words: [String]` — text split into word array for RSVP.

### RSVP Engine (Shared)

`RSVPEngine` (ObservableObject):
- **State**: `.idle`, `.playing`, `.paused`
- **Inputs**: word array, starting index, target WPM
- **Outputs**: current word, current index, ORP index, computed delay
- **Controls**: play, pause, seek to index, adjust WPM live
- Uses `Task.sleep(nanoseconds:)` for timing — cancellable and precise

## iPhone App

### Screens

1. **Library** — grid/list of imported books (title, author, progress). Import button opens document picker for EPUB/PDF. Swipe to delete.

2. **Reader** — scrollable text view of full book content. Font size control (A-/A+). Floating "RSVP" button launches RSVP mode from current scroll position. Toolbar with title and back.

3. **RSVP View** — full-screen Spritz-style redicle. Tap to pause/play. WPM adjustment. Progress bar. Close returns to reader at updated position.

### Import Flow

Document picker → detect file type → extract text → create Book in SwiftData → appear in library.

## Watch App

### Screens

1. **Now Reading** — current book title, progress, large Play button. If no book synced: "Open SpeedRead on iPhone to add books."

2. **RSVP Playing** — full-screen redicle. Digital Crown scrubs through words. Tap to pause. WPM shown subtly at top.

3. **Paused State** — large Play button centered. Top-left: Settings (gear) → WPM adjustment via Digital Crown with haptic detents. Top-right: Back.

### Sync

- iPhone sends extracted text + metadata via `transferFile()`
- Reading position synced via `updateApplicationContext()` (bidirectional)
- `sendMessage()` for real-time sync when both apps are active

## Configuration

- **WPM range**: 100-1000, default 300
- **WPM step**: 25 (Digital Crown detents on Watch)
- **Deployment targets**: iOS 17.0, watchOS 10.0

## Project Structure

```
SpeedRead/
├── Shared/
│   ├── Models/
│   │   └── Book.swift
│   ├── Engine/
│   │   ├── RSVPEngine.swift
│   │   ├── ORPCalculator.swift
│   │   └── WordTimer.swift
│   ├── Extraction/
│   │   ├── TextExtractor.swift
│   │   ├── EPUBExtractor.swift
│   │   └── PDFExtractor.swift
│   ├── Connectivity/
│   │   └── WatchSyncService.swift
│   └── Views/
│       └── RSVPWordView.swift
│
├── SpeedRead (iOS)/
│   ├── SpeedReadApp.swift
│   ├── Views/
│   │   ├── LibraryView.swift
│   │   ├── ReaderView.swift
│   │   └── RSVPView.swift
│   └── Services/
│       └── DocumentImporter.swift
│
├── SpeedRead Watch/
│   ├── SpeedReadWatchApp.swift
│   └── Views/
│       ├── NowReadingView.swift
│       ├── WatchRSVPView.swift
│       └── WatchSettingsView.swift
│
└── SpeedReadTests/
    ├── ORPCalculatorTests.swift
    ├── WordTimerTests.swift
    ├── RSVPEngineTests.swift
    ├── TextExtractionTests.swift
    └── WatchSyncServiceTests.swift
```

## Testing Strategy

### Unit Tests
- ORP calculation: every word length bucket, leading punctuation, edge cases
- Timing engine: base delay, multipliers, stacked multipliers
- Text extraction: EPUB and PDF parsing, malformed file handling
- Word splitting: punctuation preservation, whitespace, unicode

### Integration Tests
- RSVP playback: word advancement, pause/resume, seek
- SwiftData persistence: save/load books, position persistence
- WatchConnectivity: transfer/receive cycle

### UI Tests
- Import flow, RSVP flow, Watch play/pause

### Quality Principles
- Protocol-oriented design for testability
- Dependency injection — no singletons in business logic
- Structured concurrency throughout
- No force unwraps in production code
