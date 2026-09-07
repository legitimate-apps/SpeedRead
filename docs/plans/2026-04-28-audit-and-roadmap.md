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
| B2 | High | EPUB | `EPUBExtractor.swift:65-147` | ZIP reader does O(n²) byte scans; no Central Directory fallback; full byte copy in memory | **fixed** 2026-08-29 (leg 3) — `readCentralDirectory` locates the EOCD record (`0x06054b50`) and walks central-directory entries (`0x02014b50`), replacing the linear signature scan; the local-header scan remains only as a fallback for archives with no readable central directory. Verified by reading the source 2026-08-31. |
| B3 | High | EPUB | `EPUBExtractor.swift:236-272` | Spine href resolution doesn't normalize `..` paths; chapters can be silently dropped | **fixed** 2026-08-29 (leg 3) — href resolution now walks path components, collapsing `.` and `..`, and *throws* `EPUB path escapes archive root` rather than silently dropping a chapter. The silence was the bug: a dropped chapter shifts every later word index with nothing to notice. Verified by reading the source 2026-08-31. |
| B4 | Med | Gesture | `RSVPPresentationSession.swift` (was `RSVPView.swift:262-298`) | **Root cause was misdiagnosed in this row.** Resetting `lastDragX` is *required* — `DragGesture.Value.translation` restarts at zero each gesture. The actual defect was the **missing `lastDragTime` reset**, so a new drag inherited the previous gesture's timestamp, computed ~1600 pt/s of phantom velocity, and dropped effective resolution from 8 pt/word to 2.5 — jumping six words instead of two. Fixed red-first in `f063ad6`; the test drives samples *across* a gesture boundary, which is the only way this class of bug is visible. | fixed |
| B5 | Med | Engine | `SpeedRead/Engine/RSVPEngine.swift:22-25,47-50,147-153` | At end-of-book, progress < 1.0 because index = count - 1 | fixed — **but only in the engine.** The identical defect survived in `Book.progress`, which is what the reader actually displays, and was found by leg 23 coverage work on 2026-09-06 and fixed in leg 24 (`Book.finishedAt`). This row was never wrong; it was fixed where someone looked. **When a defect is a property of a model rather than of a type, fixing the type it was reported against leaves its siblings broken** — the same shape as the `SpineColor` iOS/watch drift. |
| B6 | Med | RSVP dismiss | `SpeedRead/Engine/RSVPEngine.swift:83-95`; `SpeedRead/Views/RSVPView.swift:81-85` | Pause-then-read may capture a tick that already advanced; read currentIndex before pausing | fixed |
| B7 | Med | Reader scroll | `SpeedRead/Views/ReaderView.swift:48-61` | `asyncAfter(0.05)` hack to scroll after layout — race-prone | fixed |
| B8 | Med | Persistence | `SpeedRead/Views/ReaderView.swift:293-300` | `try? modelContext.save()` swallows save errors silently | fixed |
| B9 | Low | Tap | `SpeedRead/Views/ReaderView.swift:156-184` | Words use `hSpacing: 0`; tap between glyphs ambiguous | fixed |
| B10 | Low | RTF | `SpeedRead/Services/DocumentImporter.swift:26-40`; `SpeedRead/Views/LibraryView.swift:107-110` | `.rtfd` advertised but is a directory bundle; `Data(contentsOf:)` will fail | fixed |
| B11 | Low | TXT | `SpeedRead/Extraction/TextFileExtractor.swift:30-35,54-71` | Title heuristic catches "CHAPTER ONE" / epigraphs as titles | fixed |
| B12 | Low | Animation | `LibraryView.swift:84` | `.animation(value: bool)` doesn't animate enum-state transitions | pending |
| B13 | Low | Library | `SpeedRead/Views/LibraryView.swift:18,42-45` | `loadSampleBooksIfNeeded` runs on every appear; should run once at app launch | fixed |
| B14 | Low | A11y | `SpeedRead/Views/ReaderView.swift:156-184` | `onTapGesture` instead of `Button` breaks Voice Control / focus / keyboard | fixed |
| B15 | Low | Gesture | `RSVPView.swift` / `RSVPPresentationSession.swift` | Tap and scrub were two independent recognizers on one surface. Now a single `DragGesture(minimumDistance: 0)` whose completed movement is classified against `ReaderConfig.RSVP.scrubActivationDistance` — below it is play/pause, at or above is scrub-only. Fixed red-first in `f063ad6`. | fixed |
| B16 | Low | UI dup | `ReaderView.swift:418-495` vs `BookmarkListView`/`HighlightListView` | Two divergent list implementations for the same model | pending |
| B17 | High | iPad layout | `SpeedRead/Views/LibraryView.swift:21-27,172-203`; `SpeedRead/Views/BookshelfRowView.swift:13-20,26-50`; `SpeedRead/Views/BookSpineView.swift:12-15,44-56,74` | iPad library is phone-scale and top-heavy: fixed four-book chunks, model-only rows with no viewport fill, fixed 60×120-180 pt spines, fixed 9/7 pt type, leading-edge packing plus one trailing `Spacer`, a full-width plank masking narrow content, no adaptive grid/size-class branch, and no vertical-fill policy. Estimated fix: ~25-50 lines across `LibraryView` / `BookshelfRowView` / `BookSpineView`. | fixed |
| B18 | Med | Swift 6 / SwiftData | `SpeedReadIntegrationTests/OPDSLiveIntegrationTests.swift` (moved out of the hermetic target 2026-08-29 — **re-check whether the warnings survived the move before working this**) | Three warning groups become errors in Swift 6 mode: unavailable `Book: Sendable`, non-Sendable `ModelContext` captured by an `@Sendable` closure, and non-Sendable `Book` captured by the generated `#expect` closure. | pending |
| B19 | Low | watchOS assets | `SpeedRead/Assets.xcassets` (Xcode 26.6 watch build diagnostic; no source line) | Asset catalog warns: `Could not get trait set for device Watch7,18 with version 26.5`. | pending |
| B20 | **High** | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:390` | **A rejected book is reported as successfully sent.** The `sendMessage` reply handler logs the reply and unconditionally sets `sendState = .sent(title)`; it never inspects it. The receiver answers `["status": "error"]` when `BookPayload.decode` returns nil, so the reader is told a book reached the watch that the watch refused. `SendState` already has `.failed`. The rejection is deterministic (the payload did not decode), so falling back to `transferFile` would fail identically — surface the failure. Found by leg 25 coverage work; pinned by `rejectedBookReplyIsCurrentlyMisreportedAsSent`. **Affects the live 1.2 build.** | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B21 | Med | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:611` | **An older incoming position replaces a newer pending offer.** Reconciliation compares the incoming payload against the stored book timestamp but not against the pending offer's. Reproduction: stored `20/100`; receive `80/300` then `60/200`; the offer regresses to `60/200` and accepting it moves the book back to word 60. Rule belongs in `WatchSyncLogic`. Pinned by `pendingOfferCurrentlyRegressesWhenContextsArriveOutOfOrder`. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B22 | Med | EPUB | `SpeedRead/Extraction/EPUBExtractor.swift:282` | **Local-header fallback accepts invalid ZIP data descriptors.** With bit 3 set, the reader computes a 12/16-byte skip without checking the descriptor's existence, CRC or sizes. Confirmed accepting a missing descriptor, twelve zero bytes, and a signature plus twelve zero bytes — by a standalone macOS probe compiling the unchanged production extractor. Rejecting a corrupt EPUB is correct; accepting it and producing garbage text is not. Pinned by `localHeaderCurrentlyIgnoresRequiredDescriptorIntegrity`. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B23 | Med | Watch display | `SpeedReadWatch Watch App/Shared/WatchBook.swift:69`; `WatchBookDetailPresentation.swift:6`; `WatchLibraryPresentation.swift:10` | **The watch shows "99% complete" for a finished book** — `WatchBook.progress` is `lastReadIndex / wordCount` with `lastReadIndex` clamped to `wordCount - 1` (`WatchSyncService.swift:216`), so it can never reach 1.0. This is the SAME defect leg 23 found in `Book.progress` and leg 24 fixed there; the watch is the sibling that survived, exactly as the B5 annotation predicts. Found by static audit on 2026-09-06, no simulator needed. Note a partial fix is available without transport: the watch's own `RSVPEngine.didFinish` can mark a book finished when it is finished ON the watch. Cross-device completion (finishing on the phone, seeing it on the watch) needs `finishedAt` in `PositionPayload` and is the deferred watch-parity leg. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |

## B. Improvements (code quality, polish)

| ID | Type | Description | Status |
|----|------|-------------|--------|
| I1 | Perf | Move tokenization off main actor for very large books | pending |
| I2 | Architecture | Persist tokenized words at import time, not per-open (`SpeedRead/Models/Book.swift:17-20,42-44`; `SpeedRead/Services/DocumentImporter.swift:50-58`) | fixed |
| I3 | Architecture | Extract `ReaderSession` view-model from `ReaderView` | fixed — `ReaderSession.swift` at 100% line coverage; `ReaderView.swift` fell 542 → 349 lines and is now presentation over an injected session |
| I4 | UX | Split RSVP tap-zone (top half play/pause, bottom half scrub) | **won't do** — superseded by B15's fix. One recognizer distinguishes tap from scrub by distance threshold, so the zone split would make users learn spatial regions and shrink each action's effective surface for no gain. Deliberate design decision, 2026-08-29. |
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
| I27 | Code | Split `ReaderView.swift` (palette, settings sheet, pickers into own files) | fixed — split into `ReaderTheme.swift`, `ReaderSheets.swift`, `ReaderSession.swift`, `ReaderConfig.swift` |
| I28 | Code | Unify reader theme + shelf theme into one system | pending |
| I29 | Code | Constants → `ReaderConfig` namespace | fixed — `ReaderConfig.swift` holds reader + RSVP behaviour constants, and tests assert against it, so changing a threshold is a visible diff rather than a buried modifier argument |
| I30 | DX | SwiftUI `#Preview` for `ReaderView` | pending |
| I31 | Test | **STANDING GOAL (operator):** automated Apple Watch and phone↔watch sync coverage, LANDED 2026-08-13 (15 tests: codec, reconciliation, fallback routing, watchlibrary.json recovery) AND verified end-to-end on a paired iPhone+Watch simulator: watch-sent index 137 persisted to the phone's SwiftData store (0->137, timestamp exact), a 1h-stale context was rejected (stayed 137), and a newer context applied (137->88) as a positive control proving delivery was live. Evidence is direct sqlite reads of the phone's default.store. Covers transfer, persistence, update, failure, and recovery paths | pending |
| I32 | Integration | **STANDING GOAL (operator):** “see my Calibre library in SpeedRead” remote-library integration; remain generic-OPDS-first, with Calibre-Web-NextGen as the recommended path | pending |
| I33 | Docs | **OPERATOR-GATED — DO NOT START:** full general Calibre-Web-NextGen setup tutorial. SpeedRead ships only a brief local-instance tutorial; the operator will write the fuller walkthrough. | pending |
| I34 | Correctness risk | **The last-word clamp is written out eleven times, and one of them was already wrong.** Consolidated 2026-09-07 onto `ReadingPositionCoordinator.clampedIndex`, now in `Engine/` and symlinked into the watch tree. The original entry said six copies that "all agree today"; both halves were wrong. `CrownSeek` (x2) and `WatchBook` (x3) held five more, and `WatchSyncService:609` had no lower bound while `:218` and `:656` did. VERIFIED reachable through the type's own API — `PositionPayload`'s typed initializer does no validation, so an internal caller reaches `applyIncomingPosition` and gets an offer at index -1 — but NOT through the shipping transport, since `decode(from:)` rejects `wordIndex < 0` and `continueFromWatch` re-clamps before persisting. Ruled a latent hazard, not a shipping bug, and fixed anyway: for every non-negative input the change is a strict narrowing. The decoder's check is now pinned by its own test so the invariant the other sites relied on cannot be deleted silently, and the two-sided rule is recorded in `CLAUDE.md`. | fixed 2026-09-07 |
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
- **2026-08-13** — Watch<->phone position sync verified END-TO-END on a paired simulator (not just unit-tested): apply, stale-reject, and a positive-delivery control, all read directly from the phone's SwiftData store. Closes the caveat recorded on commit `77da524`.
- **2026-08-29** — Round 8, TDD mandate. Coverage had **never been measured** on this project: no
  `.xctestplan` existed and neither shared scheme set `codeCoverageEnabled`. Honest baseline was
  **17.77%** (1486/8362 iOS lines), with the entire SwiftUI view layer at 0% — 74% of the code.
  Landed: four test-plan lanes (`Hermetic` as scheme default and offline, `Integration` in its own
  target, `UI`, `WatchHermetic`), so the default lane went from 150 tests with 5 silent env-gated
  skips to 144 with none; `Scripts/coverage.sh` with a visible and deliberately empty exclusion
  list; the watch lane executing for the first time (0% → 7.06%, tests that already existed);
  `ReaderSession` and `RSVPPresentationSession` extracted at 100% coverage each, with `ReaderView`
  0% → 85.82% and `RSVPView` 0% → 86.39%; B4 and B15 fixed red-first; all five CORPUS §4.6
  `DispatchQueue.main.asyncAfter` violations replaced with cancellable `.task(id:)`; three
  invariants that existed only as code comments now pinned by tests, one with a negative control.
  A duplicate-commit defect not on this roadmap was found and fixed en route: RSVP Close committed
  the snapshot and then `onDisappear` committed and synced it again.
  Coverage after: **42.91%** headline, **81.42%** attributable, reach 19.3% → 46.7%. Verified
  independently by the manager, not taken from the implementer's report.
- **2026-08-31** — Round 8 continued. First **mutation gate** run (`Scripts/mutation-gate.py`,
  22 manager-chosen mutations): **18 killed, 4 survived, 0 invalid**. One survivor is a proven
  equivalent mutant (`ORPCalculator`'s focus clamp is dead code — `orpIndex <= count-1` always);
  three are real gaps now queued (`WordTimer`'s `>= 8` boundary, `OPDSClient` accepting 3xx as
  success, and the never-exercised `init(session:)` default). Self-hosted `speedread-mac` runner
  registered and `.github/workflows/ci.yml` enabled, gating **attributable** coverage via
  `Scripts/coverage.sh` rather than re-implementing the lanes. Roadmap truth sweep: B2 and B3 were
  still marked pending though leg 3 fixed both — corrected above against the source.
- **2026-08-31** — Leg 8: **chapters** land end to end (EPUB 3 nav documents, EPUB 2 NCX, genuine
  heading fallback, PDFKit outline; TXT/RTF synthesize nothing, so the watch row hides rather than
  faking structure), plus a persisted `Book.chapters`, chapter marks carried on the watch sync
  payload, a pure `ChapterIndex`, and a browse-only chapter row on the watch that commits no reading
  position. Token-stream identity proven by SHA-256 fingerprints of both the raw text and the
  length-framed token sequence; `BundledSampleBookTests.swift` passed **unmodified** and appears in
  no leg-8 commit. Two silent hazards found and pinned: chapter offsets must be counted in
  post-hyphen-split tokens (the watch tokenizer disagreed with the phone's on `self-awareness`, which
  would have displaced every chapter coordinate on the watch), and an empty EPUB spine item shares a
  `startWordIndex` with the next chapter. **The Digital Crown direction is now OBSERVED end to end**
  — a watch XCUITest in its own `WatchUI.xctestplan` drives `XCUIDevice.rotateDigitalCrown` against
  the real `.digitalCrownRotation` composition, closing the project's last ASSUMED link. Mutation
  gate re-measured from a cleared ledger: 21 killed / 1 expected survivor / 0 invalid / 0 unexpected,
  unchanged by the feature. 238 iOS + 45 watch + 1 UI test; 298 tests, 0 assertion-free; combined
  attributable 83.73%; CI floor ratcheted 80 -> 82.
- **2026-08-31** — Leg 9: **reach**. Presentation logic extracted out of `LibraryView`,
  `BrowseServerView`, `ServerEditView`, `WatchLibraryView`, `WatchBookDetailView` and
  `SampleBookLoader` into directly-testable types. iOS reach 51.36% -> **62.23%**, watch reach
  47.69% -> **79.03%**, combined attributable 83.73% -> **84.43%** (it ROSE while the denominator
  grew), 283 -> 304 tests, 0 assertion-free. Mutation gate unchanged at 21 killed / 1 expected
  survivor / 0 unexpected, re-measured from a cleared ledger. Fixed a real user-facing defect found
  while extracting: the OPDS fallback search URL duplicated the catalog segment
  (`…/opds/opds/search/…`), so search silently 404'd on any server not advertising a search link.


- **2026-09-07 — Leg 28 (OBSERVED):** I34 consolidated onto a single shared clamp; original negative decoder-boundary test retained and direct-call reproducer made green. File-transfer completion and receipt now have mutation-named assertions through actual delegate methods using SDK subclasses. SpineColor is 14/14 on both targets. Combined ATTRIBUTABLE 11816/12905 → 11934/12911; required honesty, coverage 89, and UI scripts pass. See [the numbers and what moved them](../testing/TDD-MISSION.md#5aw-the-clamp-was-written-eleven-times-and-one-of-them-was-already-wrong-2026-09-07-leg-28) and [all uncovered-line dispositions](../testing/leg28-coverage-ledger.md). The entry originally cited a `2026-09-07-leg28-results.md` that was never written; the receipts it promised are in the TDD-MISSION section above.
