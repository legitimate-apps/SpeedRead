# SpeedRead

A SwiftUI e-reader for iPhone, iPad, and Apple Watch with both classic
paragraph reading and **RSVP** (Rapid Serial Visual Presentation) speed-reading
modes. Tap any word in the reader to flick into RSVP starting from that word;
close RSVP and the reader resumes at the last word you saw, highlighted in red.

> Status: shipping. Live on the App Store as 1.1; 1.2 staged. Universal iOS app +
> watchOS companion. 117 tests across unit + UI suites.

## Features

- **Classic reader** — paragraph-rendered, tap-to-RSVP on any word, font size and
  line spacing controls, three reading themes (parchment, sepia, night).
- **RSVP mode** — one word at a time at 100–1500 WPM, with **ORP** (Optimal
  Recognition Point) alignment so the focal letter sits where your eye naturally
  lands. Pinch-WPM, tap to play/pause, drag horizontally to scrub.
- **Bookmarks & highlights** — capture a single word or a range, jump back to
  either from a sheet in the reader or RSVP.
- **Apple Watch app** — independent library, RSVP via the Digital Crown for
  scrub, position syncs back to the phone.
- **Phone → Watch send** — long-press a book on the phone to push it to a paired
  watch (`WCSession.sendMessage` with `transferFile` fallback).
- **Multiple formats** — `.pdf`, `.epub`, `.txt`, `.rtf`. EPUBs are parsed with a
  pure-Swift ZIP/Deflate reader; text files with charset fallback (UTF-8 → Latin-1
  → MacRoman).
- **Bundled samples** — *The Yellow Wallpaper*, *The Metamorphosis*, *A Christmas
  Carol* (EPUB and PDF) load on first launch.

## Requirements

- Xcode 16 or later
- iOS 17.6+ (universal: iPhone, iPad, Vision)
- watchOS 10.6+ (paired watch is optional)
- Swift 5

## Build & run

```bash
git clone <this-repo>
cd SpeedRead
open SpeedRead.xcodeproj
```

Pick the `SpeedRead` scheme + an iPhone simulator and hit ▶. To run the watch
app, switch to the `SpeedReadWatch Watch App` scheme; pair an Apple Watch
simulator with the iPhone simulator first:

```bash
xcrun simctl list pairs
xcrun simctl pair <watch-udid> <phone-udid>
xcrun simctl boot <phone-udid>
xcrun simctl boot <watch-udid>
```

## Tests

```bash
# Hermetic unit tests with code coverage (the SpeedRead scheme default)
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -destination 'platform=iOS Simulator,id=<ios-udid>' \
  -parallel-testing-enabled NO

# UI tests (XCTest) — explicit lane
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -testPlan UI \
  -destination 'platform=iOS Simulator,id=<ios-udid>' \
  -parallel-testing-enabled NO

# iOS + watchOS coverage report and threshold gate
Scripts/coverage.sh 80
```

## Project layout

```
SpeedRead/                    iOS app source
  Models/                     SwiftData @Model: Book, Bookmark, Highlight
  Engine/                     RSVPEngine, WordTimer, ORPCalculator
  Extraction/                 PDF / EPUB / RTF / TXT extractors
  Services/                   DocumentImporter, SampleBookLoader
  Views/                      Library, Reader, RSVP, pickers, onboarding
  Connectivity/               WatchSyncService (WCSession bridge)
  Theme/                      Color palette, fonts, shelf themes
  Resources/                  Assets, fonts
SpeedReadWatch Watch App/     watchOS source (mirrors iOS where shared)
SampleBooks/                  Bundled .epub / .pdf
SpeedReadTests/               Hermetic Swift Testing unit tests
SpeedReadIntegrationTests/    Environment-gated live OPDS integration tests
SpeedReadUITests/             XCTest UI tests
Scripts/coverage.sh           iOS + watchOS line-coverage instrument
docs/plans/                   Live design + plan + audit docs
```

## Tech stack

- **SwiftUI** + **SwiftData** for views and persistence
- **`@Observable`** macros for view models (`RSVPEngine`)
- Custom **SwiftUI `Layout`** (`WordFlowLayout`) for the tappable wrapping word grid
- **WatchConnectivity** (`WCSession`) for phone ↔ watch sync
- **Compression** framework for in-memory EPUB unzip (no third-party deps)
- **PDFKit** for PDF extraction
- **Swift Testing** (`@Suite` / `@Test` / `#expect`) for unit tests, **XCTest**
  for UI tests

Zero external dependencies — everything ships in the Apple SDKs.

## Architecture notes

- **Word indices are the universal coordinate.** `Book.tokenize(_:)` is the single
  source of truth; tokens are persisted on the `Book` model so reader and RSVP
  align without re-tokenizing the entire body each open.
- **Reader ↔ RSVP handoff** is index-based: tap a word → store
  `lastReadWordIndex` → present RSVP starting there → on close, re-read the engine
  index atomically (`snapshotIndexAndPause()`) → write it back → reader scrolls to
  the new last-read word and renders it red.
- **Watch sync** uses `sendMessage` when the watch is reachable, with a
  `transferFile` fallback for background delivery. Position deltas use
  `updateApplicationContext` so the most-recent value always wins.

## Distribution

A TestFlight deploy slash-command lives at
`.claude/commands/deploy-app-to-testflight-legitimate.md`. Export options are
in `ExportOptions.plist`. The pipeline uses native `xcodebuild archive` plus an
App Store Connect API key from `~/.appstoreconnect/`.

## License

Private — not licensed for redistribution.
