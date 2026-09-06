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
| `SpeedReadIntegrationTests` (live OPDS, Swift Testing) | `com.legitimateapps.SpeedReadIntegrationTests` | iOS 26.2 |
| `SpeedReadUITests` (XCTest) | `com.legitimateapps.SpeedReadUITests` | iOS 26.2 |

- Swift 5, Xcode 16+ (uses `PBXFileSystemSynchronizedRootGroup` — files dropped into
  source dirs auto-include).
- `MARKETING_VERSION` = 1.2, `CURRENT_PROJECT_VERSION` = 4.

## Release state

Live on the App Store as **1.2 (build 4)**, released 2026-09-06 under Legitimate LLC (team
`3LTL47SJ8C`, ASC app `6771221242`, listed as "SpeedRead RSVP: books in a day", seller
"Legitimate Apps LLC"). 1.2 is the first release since 1.1 (2026-05-21) that carries user-facing
change. Build 3 was never submitted: it was user-facing-identical to the live 1.1, so shipping it
would have burned a review cycle on a no-op.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the table above are the SHIPPED values. Bump
both before the next archive.

> Before any future submission, diff the candidate build's **source** against the live build's
> source — not just the version number.

Marketing assets are re-runnable in-repo, not one-off: `marketing/compose.py` builds the App Store
gallery from `marketing/raw/` and `marketing/METADATA.md` is the single source for the listing copy.
`marketing/upload_asc.py` pushes both. The 2026-05 gallery was composited in `/tmp` and was gone by
the time 1.2 needed it — that is why the compositor lives in the repo now. ASC screenshot wells were
probed, not read from docs: there is no `APP_IPHONE_69` and no 13" iPad; the live wells are
`APP_IPHONE_67` (1290×2796), `APP_IPAD_PRO_3GEN_129` (2048×2732), `APP_WATCH_SERIES_10` (416×496).

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
SpeedReadTests/                // Hermetic Swift Testing unit tests (#expect)
SpeedReadIntegrationTests/     // Environment-gated live OPDS tests; explicit lane only
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
# Default lane: hermetic iOS unit tests with app + watch-app coverage instrumentation.
# Hermetic.xctestplan is the scheme default, so no -testPlan or -only-testing is needed.
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -destination 'platform=iOS Simulator,id=<ios-udid>' \
  -parallel-testing-enabled NO

# Live OPDS integration lane (requires all four environment variables).
SPEEDREAD_LIVE_OPDS=1 \
SPEEDREAD_TEST_OPDS_URL=... \
SPEEDREAD_TEST_OPDS_USER=... \
SPEEDREAD_TEST_OPDS_PASSWORD=... \
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -testPlan Integration \
  -destination 'platform=iOS Simulator,id=<ios-udid>' \
  -parallel-testing-enabled NO

# iOS UI lane — explicit because it is intentionally absent from the default lane.
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -testPlan UI \
  -destination 'platform=iOS Simulator,id=<ios-udid>' \
  -parallel-testing-enabled NO

# watchOS hermetic unit lane with watch-app coverage.
xcodebuild test \
  -project SpeedRead.xcodeproj \
  -scheme 'SpeedReadWatch Watch App' \
  -destination 'platform=watchOS Simulator,id=<watch-udid>' \
  -parallel-testing-enabled NO

# Run both hermetic destinations, print worst-first per-file coverage, and enforce a gate.
# CI runs exactly this line; the floor is ATTRIBUTABLE coverage, never headline.
Scripts/coverage.sh 88

# Run both UI plans. Deliberately NOT part of coverage.sh: a UI test drives the whole app
# through its host, so every view it walks past records as covered with nothing asserting.
Scripts/ui-lanes.sh
```

`Scripts/coverage.sh` accepts `SPEEDREAD_IOS_DESTINATION` and
`SPEEDREAD_WATCH_DESTINATION` as complete xcodebuild destination strings. It also accepts
`SPEEDREAD_DERIVED_DATA_PATH` and `SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH`; otherwise it uses
`dd-lease` when available. The script runs the iOS and watchOS lanes serially.

Pre-allowed in `.claude/settings.local.json`: `Bash(xcodebuild test:*)`.

### Honesty gates — cheap, no simulator, run before any build

```bash
Scripts/honesty-gates.sh    # runs all seven, cheapest first. RUN THIS BEFORE EVERY PUSH.
```

It is the single list; CI runs the same script. Individually:

```bash
actionlint                                # workflow files parse and their contexts exist
python3 Scripts/assertion-audit.py .      # no test may be assertion-free, or end on a sleep
python3 Scripts/lane-audit.py             # every target in a plan, every plan in a lane
python3 Scripts/shared-source-audit.py    # no filename may exist in both trees as two real files
python3 Scripts/network-isolation-audit.py # no test-tree session can reach the wire un-stubbed
Scripts/executed-tests-control.sh         # the executed-test parser reports true counts
python3 Scripts/attributable-coverage.py --self-test   # classifier reads code not comments; and
                                                       # holds non-shipping files out of the grade
```

**`actionlint` is the one gate CI cannot run for itself.** If `ci.yml` is unparseable GitHub
creates no run at all, so a CI step that lints the workflow never executes — CI does not fail, it
silently stops existing, and the push looks entirely normal. That happened here on 2026-09-04:
`${{ runner.temp }}` in a workflow-level `env:` block, where the `runner` context does not exist.
Three days of "green" meant "never ran". Run the gates locally before pushing.

These exist because a test can be real, correct, and still incapable of failing a build. Four
separate things have to be true, and each has broken here at least once:

```
target exists -> in a test plan -> plan invoked by a lane -> lane executes tests
                                                          -> and the test is aimed at the
                                                             copy that ships on that platform
```

A seventh thing has to be true before any of the others matter: **the workflow file has to be valid**,
or none of the gates run and their absence is invisible. That is `actionlint`, and it is why the
gates must be run locally rather than trusted to CI.

A sixth thing has to be true and is not on that line at all: the count of executed tests has to
be *real*. Both lanes decide "this lane is green" from a parser, and a parser that fails open
certifies an empty lane — so `Scripts/lib/executed-tests.awk` is the single copy of it and
`executed-tests-control.sh` asserts expected counts against fixture logs, including the exact
regex-literal bug that once made it return 1 for every input.

An eighth thing has to be true for a green lane to mean anything: **the tests have to be hermetic**.
A suite that can reach the network is a suite whose result depends on someone else's server, and it
fails in the direction nobody audits — green when the network happened to answer. `network-isolation-
audit.py` holds the two platform rules apart, because they are genuinely different facts: on iOS,
global `URLProtocol` registration covers `URLSession.shared` but NOT a session built from a custom
configuration, so custom sessions are centralized in the harness file; on watchOS, global
registration was observed not to intercept `URLSession.shared` at all, so the watch trees may not
use it. That audit was wired only into `Scripts/coverage.sh` until 2026-09-06 — correct, passing,
and unaffordable, since reaching it meant two simulator boots first. It is a cheap gate now.

`lane-audit.py` covers the first four; `shared-source-audit.py` covers the fifth, by refusing to
let a shared file exist as two real copies — **including byte-identical ones**, because identical
today is a copy that drifts tomorrow with nothing to notice. It audits the two TEST trees on the
same rule, and for a sharper reason: a drifted source copy renders the wrong colour, while a
drifted test copy takes an assertion out of one platform's lane and leaves that lane green. Both take exemptions only as a dict
entry carrying a written reason, and both fail on an exemption naming something that no longer
exists. `assertion-audit.py` additionally flags a test that sleeps and then asserts nothing, which
is the mechanical signature of a screenshot-capture holder wearing a test's name.

## Debug launch arguments

iOS app reads these from `ProcessInfo.processInfo.arguments` to enable scripted
verification without driving the UI:

| Flag | Effect |
|---|---|
| `-hasCompletedOnboarding YES` | Skip onboarding (set in `UserDefaults` form, two-arg) |
| `--auto-send-first-book` | Auto-fires `WatchSyncService.sendBook` on first book ~1s after launch |
| `--auto-open-first-book` | Auto-navigates into ReaderView for the first Metamorphosis (or first) book ~800ms after launch |
| `--auto-open-settings` / `--auto-open-browse` | Opens the Settings / Browse sheet ~700ms after launch |
| `--seed-test-opds-server` | **DEBUG builds only.** Seeds an OPDS server from the environment (below) so Browse/Detail can be captured without driving the Settings form |
| `--reset-onboarding` | **DEBUG builds only.** Clears the persisted `hasCompletedOnboarding` so a UI test can watch onboarding *complete*. Do NOT reach for `-hasCompletedOnboarding NO` instead: the argument domain outranks the persistent one on read, so the write onboarding performs stays masked and the app never advances — the shadow that makes the test repeatable is the same thing that makes it unable to prove anything |

Use these via `xcrun simctl launch <udid> com.legitimateapps.SpeedRead --auto-send-first-book`
to drive flows without XCUITests cloning the simulator.

### Test-server credentials live in the environment, never in the repo

The OPDS seeder and the live integration suite both read their server and credentials from
environment variables. Nothing secret is committed, and nothing secret reaches a shipping
binary — the seeder is inside `#if DEBUG`, so it is compiled out of Release entirely.

| Variable | Used by |
|---|---|
| `SPEEDREAD_TEST_OPDS_URL` | seeder + live tests |
| `SPEEDREAD_TEST_OPDS_USER` | seeder + live tests |
| `SPEEDREAD_TEST_OPDS_PASSWORD` | seeder + live tests |
| `SPEEDREAD_TEST_OPDS_NAME` | seeder only (optional, display name) |
| `SPEEDREAD_LIVE_OPDS=1` | live tests only — required to enable the suite |

```bash
# Seed the debug app on a simulator (simctl needs the SIMCTL_CHILD_ prefix)
SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_URL="https://example/opds/" \
SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_USER="someuser" \
SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_PASSWORD="secret" \
xcrun simctl launch <udid> com.legitimateapps.SpeedRead --seed-test-opds-server

# Run the live integration suite through its explicit test-plan lane
SPEEDREAD_LIVE_OPDS=1 SPEEDREAD_TEST_OPDS_URL=... \
SPEEDREAD_TEST_OPDS_USER=... SPEEDREAD_TEST_OPDS_PASSWORD=... \
xcodebuild test ... -testPlan Integration
```

The suite stays skipped unless **all** of the variables are supplied, so a partial
configuration can never silently point tests at the wrong server.

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
- `xcodebuild test -scheme SpeedRead` selects `Hermetic.xctestplan` by default. The live OPDS and
  UI suites run only when `-testPlan Integration` or `-testPlan UI` is explicit.

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
