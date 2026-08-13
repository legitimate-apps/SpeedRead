# CLAUDE.md — SpeedRead

Durable context for Claude Code sessions. Update when architecture, conventions, or
gotchas change. Keep this concise — this file is loaded into every session.

> **Read `CORPUS.md` (repo root) first.** This file is *how to work here*; `CORPUS.md` is
> *what this project is* — the thesis, design principles, architectural invariants, and the
> operator's standing goals. Facts we've learned live in the per-project memory dir.

## What this app is

**SpeedRead** is a SwiftUI e-reader for iPhone + Apple Watch with two reading modes:

1. **Classic reader** — paragraph-rendered, tappable words, parchment/sepia/night
   themes, font/line-spacing controls.
2. **RSVP** (Rapid Serial Visual Presentation) — one word at a time at a chosen WPM,
   with ORP (Optimal Recognition Point) alignment, scrub-to-seek, bookmarks,
   highlights.

Tapping any word in the reader opens RSVP starting at that word. Closing RSVP returns
to the reader with that word highlighted red as the new last-read position. Position
syncs phone ↔ watch over WatchConnectivity.

## Targets & toolchain

| Target | Bundle ID | Min OS |
|---|---|---|
| `SpeedRead` (iOS app, universal: iPhone/iPad/Vision) | `com.legitimateapps.SpeedRead` | iOS 17.6 |
| `SpeedReadWatch Watch App` | `com.legitimateapps.SpeedRead.watchkitapp` | watchOS 10.6 |
| `SpeedReadTests` (unit, Swift Testing) | `com.legitimateapps.SpeedReadTests` | iOS 26.2 |
| `SpeedReadUITests` (XCTest) | `com.legitimateapps.SpeedReadUITests` | iOS 26.2 |

- Swift 5, Xcode 16+ (uses `PBXFileSystemSynchronizedRootGroup` — files dropped into
  source dirs auto-include).
- `MARKETING_VERSION` = 1.2, `CURRENT_PROJECT_VERSION` = 3.

## Release state

Live on the App Store as **1.1 (build 2)** since 2026-05-21, under Legitimate LLC
(team `3LTL47SJ8C`, ASC app `6771221242`, listed as "SpeedRead RSVP: books in a day",
seller "Legitimate Apps LLC").

**1.2 (build 3) is uploaded and staged but deliberately NOT submitted.** Build 3 is
user-facing-identical to the live 1.1 — its only delta is debug-only screenshot launch
args — so submitting it would burn an App Review cycle on a no-op. It stays held until
real user-facing change lands. There is an open, empty review submission
(`60c34951-49dd-4b7b-88e4-d56bf6e9bce5`, `READY_FOR_REVIEW`, 0 items) to reuse when it does.

> Before any future submission, diff the candidate build's **source** against the live
> build's source — not just the version number.

> **Logger subsystem note:** `WatchSyncService` uses `com.legitimateapps.SpeedRead` as
> its logger subsystem. Matches the bundle ID. Just a logger category name, not load-bearing.

## Repo layout

```
SpeedRead/
  SpeedReadApp.swift           // @main, SwiftData modelContainer, WatchSyncService activate
  ContentView.swift            // Onboarding gate → LibraryView
  Models/                      // @Model: Book, Bookmark, Highlight
  Engine/                      // RSVPEngine (@Observable @MainActor), WordTimer, ORPCalculator
  Extraction/                  // TextExtractor protocol + PDF / EPUB / RTF / TXT impls
  Services/                    // DocumentImporter, SampleBookLoader
  Connectivity/                // WatchSyncService (WCSession, both iOS+watchOS conditionally)
  Theme/                       // Color palette, fonts, ShelfTheme, ThemeManager
  Views/                       // LibraryView, ReaderView, RSVPView, BookSpine/Bookshelf,
                               // ReaderWordFlow (custom Layout), pickers, OnboardingView
  Resources/                   // Assets, fonts
SpeedReadWatch Watch App/
  SpeedReadWatchApp.swift
  Shared/                      // WatchBook, WatchLibrary, SpineColor (mirror of iOS)
  Views/                       // WatchLibraryView, WatchBookDetailView, WatchRSVPView, WatchSettingsView
SampleBooks/                   // .epub / .pdf bundled, auto-loaded on first launch
SpeedReadTests/                // 17 test files, Swift Testing framework (#expect)
SpeedReadUITests/              // XCTest, including launch-arg-driven backdoors
docs/plans/                    // Live working docs — design + plan + audit + roadmap
.claude/commands/              // Project-scoped slash commands (TestFlight deploy)
```

`SpeedRead/Engine/RSVPEngine.swift` is shared by iOS and watchOS targets via Xcode
target membership (not a separate package).

## Architecture conventions

- **State**: SwiftUI + `@Observable` (RSVPEngine) + SwiftData `@Model`. Avoid
  `ObservableObject` for new code — `WatchSyncService` is the legacy holdout because
  WCSessionDelegate needs `NSObject`.
- **Persistence**: SwiftData container holds `Book`, `Bookmark`, `Highlight`. Tokenized
  words are persisted on `Book` (field `tokenizedWords`) — never re-tokenize per access;
  call `book.ensureTokensCached()` on appear for legacy migration.
- **Tokenization**: `Book.tokenize(_:)` is the single source of truth. RSVP and reader
  must use it (or the cached `book.words`) so word indices line up across views.
- **Reader↔RSVP handoff**:
  - Reader writes `book.lastReadWordIndex` on tap, then opens RSVP.
  - RSVP `Close` button: `engine.snapshotIndexAndPause()` → save → dismiss (atomic; do
    NOT use `engine.stop()` first — it zeros currentIndex).
  - Reader's `.onChange` of dismiss re-scrolls to the new last-read word.
- **Reader scroll race**: Use `.task(id: cachedWords.count)` to scroll-to-last-read after
  layout. Do not reintroduce `DispatchQueue.main.asyncAfter` for layout timing.
- **WordFlowLayout**: custom SwiftUI `Layout` for tappable wrapping word grid. Each word
  is a `Button` with `.buttonStyle(.plain)` (NOT `onTapGesture` — breaks Voice Control).
- **Watch sync**: tries `sendMessage` → falls back to `transferFile`. Position deltas use
  `updateApplicationContext`. Library persists on watch as `watchlibrary.json` in the
  documents directory.

## @AppStorage keys (don't rename without migration)

| Key | Type | Where |
|---|---|---|
| `hasCompletedOnboarding` | Bool | ContentView |
| `selectedThemeId` | String | ThemeManager (UserDefaults) |
| `readerFontSize` | Double | ReaderView |
| `readerLineSpacing` | Double | ReaderView |
| `readerThemeMode` | String (parchment/sepia/night) | ReaderView |
| `rsvpLastWPM` | Int | RSVPView, ReaderView |

## Build & test commands

```bash
# Run iOS unit tests (Swift Testing) — primary signal
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SpeedReadTests

# Run UI tests (XCTest) — slower, clones the simulator
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SpeedReadUITests

# Build watch app
xcodebuild build \
  -project SpeedRead.xcodeproj \
  -scheme 'SpeedReadWatch Watch App' \
  -destination 'platform=watchOS Simulator,name=Apple Watch SE (44mm) (2nd generation)'
```

Pre-allowed in `.claude/settings.local.json`: `Bash(xcodebuild test:*)`.

## Debug launch arguments

iOS app reads these from `ProcessInfo.processInfo.arguments` to enable scripted
verification without driving the UI:

| Flag | Effect |
|---|---|
| `-hasCompletedOnboarding YES` | Skip onboarding (set in `UserDefaults` form, two-arg) |
| `--auto-send-first-book` | Auto-fires `WatchSyncService.sendBook` on first book ~1s after launch |
| `--auto-open-first-book` | Auto-navigates into ReaderView for the first Metamorphosis (or first) book ~800ms after launch |

Use these via `xcrun simctl launch <udid> com.legitimateapps.SpeedRead --auto-send-first-book`
to drive flows without XCUITests cloning the simulator.

## Sample books

Loaded on first launch by `SampleBookLoader` from the app bundle:

- `TheYellowWallpaper.epub`
- `TheMetamorphosis.epub`
- `AChristmasCarol.epub`
- `AChristmasCarol.pdf`

`loadSampleBooksIfNeeded()` is idempotent (returns early if any books exist), and is
guarded by `didLoadSamples` state so it doesn't run on every `.task`.

## Format support

| Format | Extractor | Notes |
|---|---|---|
| `.pdf` | `PDFExtractor` | PDFKit |
| `.epub` | `EPUBExtractor` | Pure-Swift ZIP (Compression framework, deflate); parses container.xml → OPF → spine; HTML stripper handles common entities |
| `.txt` / `.text` | `TextFileExtractor` | UTF-8 → ISO Latin1 → MacRoman fallback. `detectTitle` rejects ALL CAPS, "CHAPTER N", "PROLOGUE", pure punctuation; recognizes "Title:" Project Gutenberg headers |
| `.rtf` | `RTFExtractor` | `NSAttributedString(documentType: .rtf)` |

`.rtfd` is **not** supported (it's a directory bundle; `Data(contentsOf:)` would fail).

## Known false positives

- **SourceKit may show "No such module 'Testing'" or "Cannot find type Book in scope"**
  in test files. These are stale-index diagnostics — builds pass. Do not "fix" by
  rearranging imports; just rebuild.
- Simulator shells occasionally crash (`system shell crashed`). Recovery:
  `xcrun simctl shutdown <udid>` then reboot.
- `xcodebuild` without `-only-testing:` runs both unit and UI tests; UI tests clone the
  simulator and can take many minutes. Default to unit-only when iterating.

## Gotchas

- **XCUITest clones simulators.** Tests that depend on watch pairing / WCSession will
  hit a phantom clone with no paired watch. Use the `--auto-*` launch flags instead.
- **Pairing is manual for the watch sim.** No Xcode auto-pair. Run
  `xcrun simctl pair <watch-udid> <phone-udid>` before testing connectivity, then boot
  both.
- **`engine.stop()` zeros `currentIndex`.** Use `pause()` or `snapshotIndexAndPause()`
  before reading the index for persistence.
- **End-of-book progress.** `RSVPEngine.didFinish` is a separate flag from
  `currentIndex`. `progress` returns 1.0 when finished, even though `currentIndex` sits
  at `count - 1`.
- **`ContentView` reads onboarding from `@AppStorage`**, but UI tests pass it via
  `-hasCompletedOnboarding YES` launch arg (UserDefaults shadow). Both work.

## Live docs

`docs/plans/` is the source of truth for in-flight work. Two are live:

- `2026-04-28-reader-overhaul.md` — reader redesign, tap-to-RSVP, red highlight,
  format support. Mostly shipped.
- `2026-04-28-audit-and-roadmap.md` — bug/improvement/feature backlog with IDs and
  per-round status. Update the Status column and the Changelog when items land.

Older plans (RSVP v1/v2, watch sync, reading-room redesign) are historical context.

## Style preferences

- Concise commits: `feat(area): summary`, `fix(area): summary`, `chore: summary`.
- Co-author tag: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`) for new code; XCTest is
  acceptable for UI tests.
- Don't add backwards-compat shims, dead code, or "removed" comments. Delete it.
- The user prefers TDD where reasonable, clean architecture, modern Swift idioms.
- Verify UI changes by screenshot through XcodeBuildMCP — low-res / high-compression
  JPEGs (`sips -Z 600 -s formatOptions 35`) to keep tokens small.

## TestFlight deploy

Slash command lives at `.claude/commands/deploy-app-to-testflight-legitimate.md`.
ASC API key at `~/.appstoreconnect/`. Uses native `xcodebuild archive` + `altool` /
`xcrun notarytool`. `ExportOptions.plist` is at the repo root.
