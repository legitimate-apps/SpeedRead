# SpeedRead Audit & Iteration Roadmap

**Created:** 2026-04-28
**Status:** Live working doc — updated each session as items are addressed
**Owner:** <owner>
**Companion doc:** `2026-04-28-reader-overhaul.md` (the original reader overhaul scope)

The project's thesis and standing goals now live in `CORPUS.md` at the repo root; this file is the working backlog.

This document is the source of truth for known issues, planned improvements, and the prioritized feature backlog. Update the **Status** column as work lands.

---

## How to use this doc

- Every audit item has an ID (B# bug, I# improvement, F# feature) and a **Status**.
- Statuses: `pending` · `fixed` · `in-progress` · `done` · `deferred` · `wontfix`.
- When work lands, append a one-line note to the **Changelog** at the bottom AND update the row.
- Add new items below the existing ones; do not renumber.

---

## A. Bugs & correctness

| ID | Sev | Area | Location | Issue | Status |
|----|-----|------|----------|-------|--------|
| B1 | High | Perf | `SpeedRead/Models/Book.swift:17-20,42-44,77-90`; `SpeedRead/Views/RSVPView.swift:127-131` | `Book.words` re-tokenizes on every access; RSVPView calls it 3× | fixed |
| B2 | High | EPUB | `EPUBExtractor.swift:65-147` | ZIP reader does O(n²) byte scans; no Central Directory fallback; full byte copy in memory | pending |
| B3 | High | EPUB | `EPUBExtractor.swift:236-272` | Spine href resolution doesn't normalize `..` paths; chapters can be silently dropped | pending |
| B4 | Med | Gesture | `RSVPView.swift:262-298` | `lastDragX` reset on `.onEnded`; first sample after drag-start has full translation as delta → visual jump | pending |
| B5 | Med | Engine | `SpeedRead/Engine/RSVPEngine.swift:22-25,47-50,147-153` | At end-of-book, progress < 1.0 because index = count - 1 | fixed |
| B6 | Med | RSVP dismiss | `SpeedRead/Engine/RSVPEngine.swift:83-95`; `SpeedRead/Views/RSVPView.swift:81-85` | Pause-then-read may capture a tick that already advanced; read currentIndex before pausing | fixed |
| B7 | Med | Reader scroll | `SpeedRead/Views/ReaderView.swift:48-61` | `asyncAfter(0.05)` hack to scroll after layout — race-prone | fixed |
| B8 | Med | Persistence | `SpeedRead/Views/ReaderView.swift:293-300` | `try? modelContext.save()` swallows save errors silently | fixed |
| B9 | Low | Tap | `SpeedRead/Views/ReaderView.swift:156-184` | Words use `hSpacing: 0`; tap between glyphs ambiguous | fixed |
| B10 | Low | RTF | `SpeedRead/Services/DocumentImporter.swift:26-40`; `SpeedRead/Views/LibraryView.swift:107-110` | `.rtfd` advertised but is a directory bundle; `Data(contentsOf:)` will fail | fixed |
| B11 | Low | TXT | `SpeedRead/Extraction/TextFileExtractor.swift:30-35,54-71` | Title heuristic catches "CHAPTER ONE" / epigraphs as titles | fixed |
| B12 | Low | Animation | `LibraryView.swift:84` | `.animation(value: bool)` doesn't animate enum-state transitions | pending |
| B13 | Low | Library | `SpeedRead/Views/LibraryView.swift:18,42-45` | `loadSampleBooksIfNeeded` runs on every appear; should run once at app launch | fixed |
| B14 | Low | A11y | `SpeedRead/Views/ReaderView.swift:156-184` | `onTapGesture` instead of `Button` breaks Voice Control / focus / keyboard | fixed |
| B15 | Low | Gesture | `RSVPView.swift:50-54` | Tap and scrub on same view conflict; quick swipes register as taps | pending |
| B16 | Low | UI dup | `ReaderView.swift:418-495` vs `BookmarkListView`/`HighlightListView` | Two divergent list implementations for the same model | pending |
| B17 | High | iPad layout | `SpeedRead/Views/LibraryView.swift:21-27,172-203`; `SpeedRead/Views/BookshelfRowView.swift:13-20,26-50`; `SpeedRead/Views/BookSpineView.swift:12-15,44-56,74` | iPad library is phone-scale and top-heavy: fixed four-book chunks, model-only rows with no viewport fill, fixed 60×120-180 pt spines, fixed 9/7 pt type, leading-edge packing plus one trailing `Spacer`, a full-width plank masking narrow content, no adaptive grid/size-class branch, and no vertical-fill policy. Estimated fix: ~25-50 lines across `LibraryView` / `BookshelfRowView` / `BookSpineView`. | fixed |
| B18 | Med | Swift 6 / SwiftData | `SpeedReadTests/OPDSLiveIntegrationTests.swift:112-113` | Three warning groups become errors in Swift 6 mode: unavailable `Book: Sendable`, non-Sendable `ModelContext` captured by an `@Sendable` closure, and non-Sendable `Book` captured by the generated `#expect` closure. | pending |
| B19 | Low | watchOS assets | `SpeedRead/Assets.xcassets` (Xcode 26.6 watch build diagnostic; no source line) | Asset catalog warns: `Could not get trait set for device Watch7,18 with version 26.5`. | pending |

## B. Improvements (code quality, polish)

| ID | Type | Description | Status |
|----|------|-------------|--------|
| I1 | Perf | Move tokenization off main actor for very large books | pending |
| I2 | Architecture | Persist tokenized words at import time, not per-open (`SpeedRead/Models/Book.swift:17-20,42-44`; `SpeedRead/Services/DocumentImporter.swift:50-58`) | fixed |
| I3 | Architecture | Extract `ReaderSession` view-model from `ReaderView` | pending |
| I4 | UX | Split RSVP tap-zone (top half play/pause, bottom half scrub) | pending |
| I5 | UX | Flash tapped word red briefly before RSVP slides up (`SpeedRead/Views/ReaderView.swift:160-178,293-310`) | fixed |
| I6 | UX | Reader header shows "X min remaining" at current WPM (`SpeedRead/Views/ReaderView.swift:71-80,271-283`) | fixed |
| I7 | UX | Long-press word → context menu (define, copy, highlight, bookmark) | pending |
| I8 | UX | Rename "Last word" pill → "Resume" (`SpeedRead/Views/ReaderView.swift:204-216`) | fixed |
| I9 | UX | Animate RSVP action-buttons reveal/hide on play/pause | pending |
| I10 | UX | RSVP highlight as press-and-hold instead of two-tap | pending |
| I11 | UX | "Reset to defaults" in reader settings sheet | pending |
| I12 | UX | Edit book title/author after import | pending |
| I13 | UX | "Couldn't extract text" empty-state with re-import affordance | pending |
| I14 | UX | Haptics on word tap, theme cycle, RSVP play/pause (`SpeedRead/Views/ReaderView.swift:293-301,322-328`; `SpeedRead/Views/RSVPView.swift:53-56`) | fixed |
| I15 | UX | Library shelf adapts to landscape (wider rows) — subsumed by the B17 adaptive layout (`LibraryLayoutMetrics` derives capacity from container width, so landscape widens rows); UI-tested in `SpeedReadUITests/LibraryAdaptiveLayoutUITests.swift` | fixed |
| I16 | A11y | Group word-level a11y per paragraph; expose words as custom actions | pending |
| I17 | A11y | Honor Dynamic Type with scaled fonts | pending |
| I18 | A11y | Brighter accent for night-theme red highlight (contrast) | pending |
| I19 | A11y | VoiceOver rotor: skip-by-sentence in RSVP | pending |
| I20 | Perf | In-memory cache of tokenized words keyed by `book.id` | done (R1) — superseded by stored `tokenizedWords` |
| I21 | Perf | Virtualize word ranges (not just paragraphs) for huge books | pending |
| I22 | Perf | Memoize `Book.progress` recomputation | pending |
| I23 | Test | Stable `accessibilityIdentifier` for first body word | pending |
| I24 | Test | Real `.epub` integration test against bundled fixtures | pending |
| I25 | Test | Fuzz `WordFlowLayout` width edge cases (0, .infinity) | pending |
| I26 | Code | Add `RSVPEngine.isLoaded` flag; don't infer from `totalWords > 0` | done (R1) |
| I27 | Code | Split `ReaderView.swift` (palette, settings sheet, pickers into own files) | pending |
| I28 | Code | Unify reader theme + shelf theme into one system | pending |
| I29 | Code | Constants → `ReaderConfig` namespace | pending |
| I30 | DX | SwiftUI `#Preview` for `ReaderView` | pending |
| I31 | Test | **STANDING GOAL (operator):** automated Apple Watch and phone↔watch sync coverage, PARTIALLY LANDED 2026-08-13 (15 tests: codec, reconciliation, fallback routing, watchlibrary.json recovery). Real paired-simulator WatchConnectivity delivery still UNVERIFIED. Covers transfer, persistence, update, failure, and recovery paths | pending |
| I32 | Integration | **STANDING GOAL (operator):** “see my Calibre library in SpeedRead” remote-library integration; remain generic-OPDS-first, with Calibre-Web-NextGen as the recommended path | pending |
| I33 | Docs | **OPERATOR-GATED — DO NOT START:** full general Calibre-Web-NextGen setup tutorial. SpeedRead ships only a brief local-instance tutorial; the operator will write the fuller walkthrough. | pending |

## C. Features

### Tier 1 — High value
| ID | Feature | Status |
|----|---------|--------|
| F1 | Search within book | pending |
| F2 | Table of Contents (EPUB has the data) | pending |
| F3 | Reading goals + streaks (calendar heatmap) | pending |
| F4 | User-facing punctuation pause slider | pending |
| F5 | Multi-word chunk RSVP mode (2–3 words for high WPM) | pending |
| F6 | Comprehension quiz mode | pending |
| F7 | Speed-ramping training plan | pending |
| F8 | Safari Share Sheet article import (Reader Mode HTML) | pending |
| F9 | Highlights/bookmarks export (Markdown / Notes / Readwise) | pending |
| F10 | iCloud sync (CloudKit via SwiftData) | pending |

### Tier 2 — Medium value
| ID | Feature | Status |
|----|---------|--------|
| F11 | Audiobook / TTS companion mode | pending |
| F12 | Vocabulary builder from word taps | pending |
| F13 | OpenDyslexic font option | pending |
| F14 | Page-flip mode for fiction | pending |
| F15 | Chapter auto-pause in RSVP | pending |
| F16 | Character/proper-noun primer before reading | pending |
| F17 | Tunable ORP / focus letter index | pending |
| F18 | Reader stats (avg WPM, words read, trends) | pending |
| F19 | Live Activity / Dynamic Island for RSVP session | pending |
| F20 | Drag-and-drop import (iPad) | pending |
| F21 | Folders / tags / collections | pending |
| F22 | "View original page" jump for PDF figures | pending |

### Tier 3 — Nice to have
| ID | Feature | Status |
|----|---------|--------|
| F23 | Custom user themes (export/share) | pending |
| F24 | Watch as RSVP controller (live, not queue) | pending |
| F25 | AirPlay / mirror mode for group reading | pending |
| F26 | Focus mode integration ("Reading" focus auto-launches RSVP) | pending |
| F27 | Spaced repetition surfacing of highlights | pending |
| F28 | CJK / multi-language tokenization | pending |
| F29 | Subscription paywall (gates: cloud sync, training, export) | pending |
| F30 | Interactive onboarding tutorial | pending |

---

## D. Iteration plan — order of operations

1. **Round 1 — Foundations** (correctness + perf)
   - B1, I2, I20 (tokenization caching)
   - B5, B6, I26 (RSVP state model cleanup)
   - B7, B11 (small papercuts)
   - B13 (sample loader)
2. **Round 2 — Reader UX polish**
   - I5 (flash tapped word red), I6 (time remaining), I8 (rename "Last word"), I14 (haptics)
   - B9, B14 (tap target / Button), I27 (file split)
3. **Round 3 — Killer features**
   - F2 (TOC), F1 (Search)
   - F8 (Share Sheet article import)
4. **Round 4 — Differentiators**
   - F4 (punctuation pause), F5 (multi-word chunk), F7 (training plan)
5. **Round 5 — Sync & accessibility**
   - F10 (CloudKit), I16/I17/I18 (a11y)
6. **Round 6 — 2026-08-13 health and backlog truth sweep** (completed)
   - Reclassified every B1-B16 and I1-I19 row against current source; added B17-B19 and standing/gated improvements I31-I33.
   - Audit basis: Xcode 26.6; 134/134 unit tests passing; watch target building clean.

Each round is its own session/PR. This doc gets the Changelog updated.

---

## E. Changelog

- **2026-04-28** — Doc created from full audit pass.
- **2026-04-28** — Round 1 started.
- **2026-04-28** — Round 1 landed: B1 / I2 / I20 (Book stores `tokenizedWords`, RSVPView uses cached array, added `Book.ensureTokensCached`); I26 / B6 (`RSVPEngine.isLoaded`, `snapshotIndexAndPause()` for atomic dismiss capture); B5 (`didFinish` flag → progress reaches 1.0 at end of book); B7 (replaced `asyncAfter` scroll race with `.task(id: cachedWords.count)`); B11 (TXT title heuristic rejects ALL CAPS / "CHAPTER N" / "PROLOGUE" / pure-punctuation lines); B13 (sample loader gated by `didLoadSamples` flag, runs once per launch). 112/112 tests passing (4 new).
- **2026-08-13** — Round 6 health and backlog truth sweep: Xcode 26.6, 134/134 unit tests passing, watch target building clean. Reclassified B1-B16 and I1-I19 from current source; added B17-B19 plus standing/gated improvements I31-I33. Project thesis and standing-goal authority moved to root `CORPUS.md`.
- **2026-08-13** — Round 7 landed: B17 (iPad adaptive bookcase layout — width-derived shelf capacity, equal centered slots, vertical fill, regular-width furniture and 112x224-300pt spines; compact width unchanged) and I15 (landscape, subsumed). Watch position sync fixed in both directions — it worked in neither — with a WCSession-free seam and 15 new tests (I31 partial). Security: server credentials removed from source and from Release binaries, verified by before/after binary inspection. 150 unit tests in 22 suites + 15 UI tests passing.
