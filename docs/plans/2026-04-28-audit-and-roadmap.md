# SpeedRead Audit & Iteration Roadmap

**Created:** 2026-04-28
**Status:** Live working doc — updated each session as items are addressed
**Owner:** <owner>
**Companion doc:** `2026-04-28-reader-overhaul.md` (the original reader overhaul scope)

This document is the source of truth for known issues, planned improvements, and the prioritized feature backlog. Update the **Status** column as work lands.

---

## How to use this doc

- Every audit item has an ID (B# bug, I# improvement, F# feature) and a **Status**.
- Statuses: `pending` · `in-progress` · `done` · `deferred` · `wontfix`.
- When work lands, append a one-line note to the **Changelog** at the bottom AND update the row.
- Add new items below the existing ones; do not renumber.

---

## A. Bugs & correctness

| ID | Sev | Area | Location | Issue | Status |
|----|-----|------|----------|-------|--------|
| B1 | High | Perf | `Book.swift:70`, `RSVPView.swift:125,304,320` | `Book.words` re-tokenizes on every access; RSVPView calls it 3× | done (R1) |
| B2 | High | EPUB | `EPUBExtractor.swift:65-147` | ZIP reader does O(n²) byte scans; no Central Directory fallback; full byte copy in memory | pending |
| B3 | High | EPUB | `EPUBExtractor.swift:236-272` | Spine href resolution doesn't normalize `..` paths; chapters can be silently dropped | pending |
| B4 | Med | Gesture | `RSVPView.swift:262-298` | `lastDragX` reset on `.onEnded`; first sample after drag-start has full translation as delta → visual jump | pending |
| B5 | Med | Engine | `RSVPEngine.swift:121-127` | At end-of-book, progress < 1.0 because index = count - 1 | done (R1) |
| B6 | Med | RSVP dismiss | `RSVPView.swift:78-82` | Pause-then-read may capture a tick that already advanced; read currentIndex before pausing | done (R1) |
| B7 | Med | Reader scroll | `ReaderView.swift:50-56` | `asyncAfter(0.05)` hack to scroll after layout — race-prone | done (R1) |
| B8 | Med | Persistence | `ReaderView.swift:276-280` | `try? modelContext.save()` swallows save errors silently | pending |
| B9 | Low | Tap | `ReaderView.swift:151-175` | Words use `hSpacing: 0`; tap between glyphs ambiguous | pending |
| B10 | Low | RTF | `DocumentImporter.swift:27-28` | `.rtfd` advertised but is a directory bundle; `Data(contentsOf:)` will fail | pending |
| B11 | Low | TXT | `TextFileExtractor.swift:45` | Title heuristic catches "CHAPTER ONE" / epigraphs as titles | done (R1) |
| B12 | Low | Animation | `LibraryView.swift:84` | `.animation(value: bool)` doesn't animate enum-state transitions | pending |
| B13 | Low | Library | `LibraryView.swift:38-40` | `loadSampleBooksIfNeeded` runs on every appear; should run once at app launch | done (R1) |
| B14 | Low | A11y | `ReaderView.swift:168` | `onTapGesture` instead of `Button` breaks Voice Control / focus / keyboard | pending |
| B15 | Low | Gesture | `RSVPView.swift:50-54` | Tap and scrub on same view conflict; quick swipes register as taps | pending |
| B16 | Low | UI dup | `ReaderView.swift:418-495` vs `BookmarkListView`/`HighlightListView` | Two divergent list implementations for the same model | pending |

## B. Improvements (code quality, polish)

| ID | Type | Description | Status |
|----|------|-------------|--------|
| I1 | Perf | Move tokenization off main actor for very large books | pending |
| I2 | Architecture | Persist tokenized words at import time, not per-open | done (R1) |
| I3 | Architecture | Extract `ReaderSession` view-model from `ReaderView` | pending |
| I4 | UX | Split RSVP tap-zone (top half play/pause, bottom half scrub) | pending |
| I5 | UX | Flash tapped word red briefly before RSVP slides up | pending |
| I6 | UX | Reader header shows "X min remaining" at current WPM | pending |
| I7 | UX | Long-press word → context menu (define, copy, highlight, bookmark) | pending |
| I8 | UX | Rename "Last word" pill → "Resume" | pending |
| I9 | UX | Animate RSVP action-buttons reveal/hide on play/pause | pending |
| I10 | UX | RSVP highlight as press-and-hold instead of two-tap | pending |
| I11 | UX | "Reset to defaults" in reader settings sheet | pending |
| I12 | UX | Edit book title/author after import | pending |
| I13 | UX | "Couldn't extract text" empty-state with re-import affordance | pending |
| I14 | UX | Haptics on word tap, theme cycle, RSVP play/pause | pending |
| I15 | UX | Library shelf adapts to landscape (wider rows) | pending |
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

Each round is its own session/PR. This doc gets the Changelog updated.

---

## E. Changelog

- **2026-04-28** — Doc created from full audit pass.
- **2026-04-28** — Round 1 started.
- **2026-04-28** — Round 1 landed: B1 / I2 / I20 (Book stores `tokenizedWords`, RSVPView uses cached array, added `Book.ensureTokensCached`); I26 / B6 (`RSVPEngine.isLoaded`, `snapshotIndexAndPause()` for atomic dismiss capture); B5 (`didFinish` flag → progress reaches 1.0 at end of book); B7 (replaced `asyncAfter` scroll race with `.task(id: cachedWords.count)`); B11 (TXT title heuristic rejects ALL CAPS / "CHAPTER N" / "PROLOGUE" / pure-punctuation lines); B13 (sample loader gated by `didLoadSamples` flag, runs once per launch). 112/112 tests passing (4 new).
