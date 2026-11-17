# SpeedRead

An e-reader for iPhone, iPad and Apple Watch with two ways to read the same book:

- **Classic reader**: paragraphs on parchment, sepia or night themes, with font and line-spacing
  controls. Every word is tappable.
- **RSVP** (Rapid Serial Visual Presentation): one word at a time at the speed you choose, with the
  word's Optimal Recognition Point (ORP) held in the same spot so your eye never moves.

Tap any word in the reader and RSVP starts there. Close RSVP and the reader comes back at the last
word you saw, marked in red. Your place follows you between the phone and the watch, and to your own
library server if you use one.

SpeedRead is on the App Store as "SpeedRead RSVP: books in a day". This repository is the full
source of the app, its tests and its release tooling.

## Features

- **Formats**: EPUB, PDF, plain text and RTF. EPUBs are read by a pure-Swift ZIP reader (the
  Compression framework, no third-party code); text files fall back from UTF-8 to Latin-1 to
  MacRoman.
- **RSVP**: 100 to 1500 words per minute, ORP alignment, long words split into hyphenated pieces,
  URLs held whole and longer, and a scrub strip that moves 1:1 with your finger.
- **Chapters, bookmarks, highlights and notes**, in both the reader and RSVP.
- **Apple Watch app**: its own library, RSVP with the Digital Crown, and a live handoff: start on
  the phone, pick up on the watch, and either device shows "Reading on …" while the other plays.
- **Library servers (OPDS)**: browse, search and download from Calibre, Calibre-Web,
  Calibre-Web-NextGen or any OPDS catalog, with covers, series and metadata.
- **Sync with your own server**: reading position over KOSync with text anchors (so a place from
  KOReader or a Kobo lands on the same word), plus highlights, notes and bookmarks with
  Calibre-Web-NextGen. There is no SpeedRead account and no SpeedRead server: your data only travels
  over infrastructure you already own or Apple already provides.
- **Bundled samples**: *The Yellow Wallpaper*, *The Metamorphosis* and *A Christmas Carol* load on
  first launch.

## Requirements

- macOS with Xcode 26 or later (the project is Swift 6 language mode)
- iOS 17.6 or later (iPhone, iPad, Apple Vision Pro)
- watchOS 10.6 or later, optional

No package dependencies: everything comes from the Apple SDKs.

## Build and run

```bash
git clone https://github.com/legitimate-apps/SpeedRead.git
cd SpeedRead
open SpeedRead.xcodeproj
```

Choose the `SpeedRead` scheme and an iPhone simulator, then Run. The project is signed for its
publisher's team, so to run on a device set your own team under *Signing & Capabilities* for the
`SpeedRead` and `SpeedReadWatch Watch App` targets, and change the bundle identifiers if Xcode asks.

To try the watch app, pair a watch simulator with the phone simulator first, then run the
`SpeedReadWatch Watch App` scheme:

```bash
xcrun simctl list devices available        # find the two UDIDs
xcrun simctl pair <watch-udid> <phone-udid>
xcrun simctl boot <phone-udid>
xcrun simctl boot <watch-udid>
```

## Tests

About 850 tests. The default lane is hermetic: no test can reach the network.

```bash
# iOS unit tests (Hermetic.xctestplan is the scheme default)
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO

# watchOS unit tests
xcodebuild test -project SpeedRead.xcodeproj -scheme 'SpeedReadWatch Watch App' \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -parallel-testing-enabled NO

# UI tests, run explicitly
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan UI \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO

# Both hermetic lanes, a per-file coverage report, and a 90% floor on attributable coverage
Scripts/coverage.sh 90
```

Use any simulator you have installed (`xcrun simctl list devices available`).

The live integration lane talks to a real OPDS server you point it at, and stays skipped unless all
of these are set:

```bash
SPEEDREAD_LIVE_OPDS=1 \
SPEEDREAD_TEST_OPDS_URL=https://your-server/opds/ \
SPEEDREAD_TEST_OPDS_USER=... \
SPEEDREAD_TEST_OPDS_PASSWORD=... \
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Integration \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO
```

### Honesty gates

`Scripts/honesty-gates.sh` runs ten cheap checks that need no simulator, and CI runs the same
script. They exist because a test can be correct and still unable to fail a build: a target missing
from a test plan, a plan no lane runs, a parser that miscounts executed tests, a test with no
assertion, a test that can reach the network, or a doc that cites a file that doesn't exist. Run it
before you push.

## Project layout

```
SpeedRead/                     iOS app
  Models/                      SwiftData models: Book, Bookmark, Highlight, OPDSServer
  Engine/                      RSVPEngine, WordTimer, ORPCalculator, ReadingPositionCoordinator
  Extraction/                  PDF, EPUB, RTF and TXT text extractors
  Services/                    Import, sample books, OPDS client and parser
  Sync/                        KOSync client, position anchors, annotation sync
  Connectivity/                WatchConnectivity bridge and live-handoff rules
  Views/                       Library, reader, RSVP, server browsing, settings, onboarding
  Theme/                       Palette, fonts, shelf themes
SpeedReadWatch Watch App/      watchOS app (shares engine code with iOS)
SpeedReadTests/                Hermetic unit tests (Swift Testing)
SpeedReadWatch Watch AppTests/ watchOS unit tests
SpeedReadIntegrationTests/     Live OPDS and sync tests, opt-in
SpeedReadUITests/              UI tests (XCTest)
Scripts/                       Coverage, honesty gates, mutation testing
marketing/                     App Store screenshot compositor and listing copy
docs/plans/                    Design notes, audit and backlog
```

## How it fits together

- **The word index is the one coordinate.** `Book.tokenize(_:)` is the single tokenizer, its output
  is stored on the book, and the reader, RSVP, the watch and server sync all address a place by word
  index, so they always agree on where you are.
- **Reader and RSVP hand off by index.** Tapping a word stores it as the last-read place and opens
  RSVP there; closing RSVP snapshots the engine's index and pauses in one step, so the place can't
  be lost to a reset.
- **Phone and watch share one place.** Positions go by `updateApplicationContext` plus a live
  message when the other device is reachable, and the newest reading wins. Books go by message with
  a file-transfer fallback.
- **Server sync converts, it doesn't guess.** A foreign position (an EPUB location, a percentage, a
  text quote) is converted to a word index and offered, never applied silently, because a sync that
  lands you somewhere else is a bug.

`CLAUDE.md` and `CORPUS.md` are the working notes the project is built with: the product's
principles and invariants, and the conventions and pitfalls for working in the code.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright 2026 Legitimate LLC.
