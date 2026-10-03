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
| B18 | Med -> **High once measured** | Swift 6 / concurrency | project-wide, not one file | **The row said three warning groups in one integration-test file. Measured 2026-09-07 with `SWIFT_STRICT_CONCURRENCY=complete` so the build completes instead of failing fast: 4,218 occurrences on iOS (562 unique) and 530 on watchOS (126 unique), plus two hard errors under `SWIFT_VERSION=6.0` from shared-mutable `ISO8601DateFormatter` statics in `OPDSAtomParser`.** The scale came from `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which isolates types nobody annotated — so the fix was `nonisolated` on the pure-logic types, not thousands of edits. A count from a failed `build-for-testing` is a floor, never a total; the first probe reported 2 errors because it stopped at the first failing module. | **fixed** 2026-09-07 (leg 30) |
| B19 | Low | watchOS assets | `SpeedRead/Assets.xcassets` (Xcode 26.6 watch build diagnostic; no source line) | Asset catalog warns: `Could not get trait set for device Watch7,18 with version 26.5`. | pending |
| B20 | **High** | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:390` | **A rejected book is reported as successfully sent.** The `sendMessage` reply handler logs the reply and unconditionally sets `sendState = .sent(title)`; it never inspects it. The receiver answers `["status": "error"]` when `BookPayload.decode` returns nil, so the reader is told a book reached the watch that the watch refused. `SendState` already has `.failed`. The rejection is deterministic (the payload did not decode), so falling back to `transferFile` would fail identically — surface the failure. Found by leg 25 coverage work; pinned by `rejectedBookReplyIsCurrentlyMisreportedAsSent`. **Affects the live 1.2 build.** | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B21 | Med | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:611` | **An older incoming position replaces a newer pending offer.** Reconciliation compares the incoming payload against the stored book timestamp but not against the pending offer's. Reproduction: stored `20/100`; receive `80/300` then `60/200`; the offer regresses to `60/200` and accepting it moves the book back to word 60. Rule belongs in `WatchSyncLogic`. Pinned by `pendingOfferCurrentlyRegressesWhenContextsArriveOutOfOrder`. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B22 | Med | EPUB | `SpeedRead/Extraction/EPUBExtractor.swift:282` | **Local-header fallback accepts invalid ZIP data descriptors.** With bit 3 set, the reader computes a 12/16-byte skip without checking the descriptor's existence, CRC or sizes. Confirmed accepting a missing descriptor, twelve zero bytes, and a signature plus twelve zero bytes — by a standalone macOS probe compiling the unchanged production extractor. Rejecting a corrupt EPUB is correct; accepting it and producing garbage text is not. Pinned by `localHeaderCurrentlyIgnoresRequiredDescriptorIntegrity`. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B23 | Med | Watch display | `SpeedReadWatch Watch App/Shared/WatchBook.swift:69`; `WatchBookDetailPresentation.swift:6`; `WatchLibraryPresentation.swift:10` | **The watch shows "99% complete" for a finished book** — `WatchBook.progress` is `lastReadIndex / wordCount` with `lastReadIndex` clamped to `wordCount - 1` (`WatchSyncService.swift:216`), so it can never reach 1.0. This is the SAME defect leg 23 found in `Book.progress` and leg 24 fixed there; the watch is the sibling that survived, exactly as the B5 annotation predicts. Found by static audit on 2026-09-06, no simulator needed. Note a partial fix is available without transport: the watch's own `RSVPEngine.didFinish` can mark a book finished when it is finished ON the watch. Cross-device completion (finishing on the phone, seeing it on the watch) needs `finishedAt` in `PositionPayload` and is the deferred watch-parity leg. | **fixed** 2026-09-07 (leg 26) — characterization test failed against the fix first, then updated to assert the corrected behaviour; see TDD-MISSION 5as |
| B24 | **High** | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:128-157` | **Completion does not cross the wire.** `PositionPayload` carries five fields — `bookId`, `bookTitle`, `wordIndex`, `timestamp`, `furthestReadWordIndex` — and no completion marker, so a book finished on one device is never finished on the other. This is the transport half of B23, which the B23 note explicitly deferred ("Cross-device completion … needs `finishedAt` in `PositionPayload` and is the deferred watch-parity leg"). Confirmed by reading the struct and its `dictionary`/`decode(from:)` pair, not by report. | **fixed** 2026-09-07 (leg 29) |
| B25 | **High** | Watch sync | `SpeedRead/Connectivity/WatchSyncService.swift:681` | **Accepting a watch position silently un-finishes a finished book.** `acceptPendingWatchPosition` sets `book.finishedAt = nil` unconditionally, so finishing a book on the phone and then accepting any incoming watch position — including one at the final word — clears the completion the user just earned. The clearing rule is right; applying it without asking what arrived is not. Distinct from B24: B24 is the missing field, B25 is what the receiver does when the field is missing. | **fixed** 2026-09-07 (leg 29) |
| B26 | Med | Watch | `SpeedReadWatch Watch App/Shared/WatchBook.swift:118` | **The watch keeps completion on a non-finishing commit at the last word.** `WatchLibrary.updatePosition` clears `hasFinishedLocally` only `if clamped < upperBound`, so committing the final index leaves it true; the phone's `ReadingPositionCoordinator.commit` (`ReaderSession.swift:57`) clears completion on every non-finishing commit regardless of index. Reachable in production: pressing Play calls `engine.play()`, which clears `didFinish`, and the resulting commit reaches that condition. Same shape as B23 and I34 — a rule written twice, diverging at the copy nobody re-read. Found by leg 29 while implementing B24; verified against source before being accepted. | **fixed** 2026-09-07 (leg 29) |
| B27 | **Critical (latent)** | Watch sync / concurrency | `SpeedRead/Connectivity/WatchSyncService.swift:606,611,612,616,629,769,786` | **Every `WCSessionDelegate` entry point ran on the wrong actor for the app's entire life.** WatchConnectivity invokes its delegate on its own queue; the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so all seven callbacks were implicitly `@MainActor` without the annotation appearing anywhere near them. Swift 5 does not enforce the executor check, so this was invisible; under Swift 6 the check is compiled into the `@objc` thunk and the app **SIGTRAPs at launch** — observed, not reasoned: `_dispatch_assert_queue_fail` -> `_swift_task_checkIsolatedSwift` -> `_checkExpectedExecutor` -> `@objc WatchSyncService.session(_:activationDidCompleteWith:error:)` -> `-[WCSession onqueue_completeSwitchTask:withSessionState:]`. The tell was in the source all along: sibling callbacks open with `Task { @MainActor [weak self] in }`, working around arriving off-main without naming why; the two that did not hop are the two that trapped. Not shipped-broken — 1.3 is Swift 5 and does not enforce the check — but the data races were real before the trap existed. Fixed by making all seven entry points `nonisolated`, decoding values at the boundary and hopping explicitly. | **fixed** 2026-09-07 (leg 30) |
| B28 | **High** | Reader navigation | `SpeedRead/Views/ReaderSheets.swift` (bookmark and highlight pickers) | **Jumping from the bookmark or highlight picker committed the reading position.** Both pickers moved `lastReadWordIndex`, so glancing at a bookmark relocated "continue where I left off" to whatever you looked at — the reader's own three-marker model (`lastReadWordIndex` commit / `browseWordIndex` browse / `furthestReadWordIndex` high-water) says navigation is browsing. Found by leg 31 while building the chapter picker: the constraint written to keep the NEW picker from doing this turned out to describe what the two existing ones already did. A feature ask is an entry point into its subsystem. | **fixed** 2026-09-07 (leg 31) |
| B29 | Med | Reader scroll | `SpeedRead/Views/ReaderView.swift` / `ReaderSession.swift` | **A distant jump could scroll to a word `LazyVStack` had never mounted, and silently do nothing.** Scrolling targeted the word anchor directly; for a target far outside the rendered window that anchor does not exist yet, so the jump was a no-op with no error. Navigation now reveals the containing paragraph first, then scrolls to the exact word. The UI test was observed red against the pre-fix tree and green after — a control in both directions, not just a passing test. | **fixed** 2026-09-07 (leg 31) |
| B30 | ~~Med~~ **WITHDRAWN — not a defect** | OPDS parsing | `SpeedRead/Services/OPDSAtomParser.swift:203` | **I claimed `OPDSEntry.language` was always nil against a real server. It is not, and never was.** The parser applies `elementName.localOPDSName` (`:203`, and again in the other two delegate callbacks) BEFORE the switch; `localOPDSName` strips everything up to the last colon and lowercases, so `dcterms:language` arrives at the switch as `language` and `case "language"` matches. I grepped for the `case` and for `shouldProcessNamespaces = false`, found both, and concluded the case could not match without reading the two lines above the switch — `localOPDSName` was in my own grep output and I read past it. Disproved by the leg-32 delegate, which ran a captured-language test against the UNCHANGED parser and got 59 language values across 60 entries, first value `eng`, then built a mutation control (both normalisation calls replaced with `lowercased()`) that drops all 59. **A diagnosis handed to a delegate is an assumption wearing a specification's clothes** — this one survived only because the brief said to verify each observation before acting on it. See B31 for the real parser defect the same investigation found. | **withdrawn** 2026-09-07 |
| B31 | Med | OPDS presentation | `SpeedRead/Views/Server/OPDSMetadataLogic.swift` | **Categories render as an unreadable run-on.** Calibre-Web splits its tag list on commas server-side, so a tag containing a comma arrives as two separate `<category>` elements — OBSERVED in the raw fixture: `term="Wall Street (New York"` and `term="N.Y.) -- Fiction"` are two elements where the real tag is `Wall Street (New York, N.Y.) -- Fiction`. The parser is faithful to the wire; joining the fragments with `", "` for display is what makes them unreadable. **Do not attempt to rejoin them.** The obvious repair — merge a term with unbalanced `(` into the one after it — was tested against the real fixture and FABRICATES a category: the server sorts alphabetically *after* splitting, so the two halves are at indices 4 and 1, and adjacency-merging yields `"Wall Street (New York, Young men -- Fiction"`, which exists nowhere. The information needed to rejoin is destroyed server-side. The fix is presentational: render each term as its own bounded element so the server's split is visible rather than disguised. Found by screenshotting the detail view — the unit tests pass on every one of these fragments. | open |
| B32 | **High** | Watch performance | `SpeedReadWatch Watch App/Views/WatchRSVPView.swift`; `Shared/WatchPresentationLogic.swift`; `Shared/WatchBook.swift` | **Watch RSVP did O(book) work for every word displayed, twice.**
(1) `WatchBook.words` was a computed property that re-tokenized the whole text, and the RSVP view read it in its body and in the per-word `onChange`. That broke CORPUS §4.2 on the watch.
(2) The view wrote the crown binding on every word, and watchOS rebuilt the crown's detent notches across the full `0...wordCount` range each time (`puic_add_notch`, `StrideThrough`).
MEASURED on a watchOS 26.5 SE 3 simulator, with a temporary 150k-word fixture playing at 1000 WPM, as a share of one Mac core: **99.0% → 27.5% after (1) → 6.3% after (2)**. Paused, it was 0.1%. `sample` attributed 2,543 of 2,595 main-thread samples to `BookTokenizer.tokenize` before the fix and 0 after.
ESTIMATED, not measured: watch silicon is several times slower than a Mac core, so on device a long book could not keep its WPM at all.
Fix: the session owns the tokens, through its engine (`wordCount = engine.totalWords`), and `WatchBook.tokenizeWords()` names its cost. The crown binding is published only when not playing, and caught up on pause. Also fixed: the legacy single-book migration stored a whitespace word count rather than the canonical token count, which clamped commits off the last tokens.
Guarded by `crownMathUsesTheLoadedTokenStream`, `crownBindingIsPublishedOnlyWhenTheCrownIsLive`, `legacySingleBookMigrationCountsCanonicalTokens` and the UI test `testCrownAfterPlaybackMovesFromThePausedWord`. That UI test was proven red against a mutant without the pause catch-up: the crown snapped back to 98 from a pause at 127+. | fixed 2026-10-03 |

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
| F1 | Search within a book (jump to a match, then read on from it). **Row added 2026-09-07: F1 was cited in the Round 3 plan below since this file was written and never had a row of its own — an ID referenced but nowhere defined, which reads exactly like an ID that was triaged.** | pending |
| F2 | Table of Contents — chapter list in the reader, current-chapter mark, chapter name in RSVP, entry hidden for chapterless books. The extraction half was already done and test-pinned; this was the UI over it. | **done** 2026-09-07 (leg 31) |
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
| F31 | Reading-position sync with the user's own library server (KOSync + text anchors; CWNG first) | client built and joint end-to-end passed 2026-10-03; awaiting the server merge and a release — [design notes](2026-10-03-reading-sync.md) |

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
7. **Round 7 — 1.4, scope set by the operator 2026-09-07**
   - Asked which of four directions 1.4 should be built around; the answer was
     **I32 (Calibre/OPDS depth)**, followed immediately by "and do chapters too".
     Both tracks are in scope; F3 (goals/streaks) and a quality-only release were not chosen.
   - F2 is a UI feature over finished data: `ChapterMark`/`ChapterIndex` exist and are
     `nonisolated`/`Sendable`, `Book.chapters` persists and crosses the watch wire, and both
     `EPUBExtractor` and `PDFExtractor` emit marks pinned by `ChapterTokenIdentityTests`.
     Nothing on iOS reads `ChapterIndex` — its only consumer is `WatchSettingsLogic`.
   - I32 needs discovery before it needs a design: the parser already handles OpenSearch
     templates and pagination links, `.searchable` is wired in `BrowseServerView.swift:170`
     with a Calibre-Web `/search/{searchTerms}` fallback, and `OPDSCoverCache` exists.
     Facets are absent. The gap is not the list I would have guessed, so measure first.

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

- **2026-09-07 — Leg 29 (OBSERVED):** cross-device completion. `PositionPayload` carries `didFinish`
  and `finishedAt`; an absent key decodes as **not finished**, so an old build on either side stays
  correct, and the encoder still writes the legacy `hasFinishedLocally` key. One shared rule,
  `ReadingPositionCoordinator.completionDate`, now governs completion on the phone commit, the watch
  commit and the accepted-offer path — replacing three divergent rules, one of which
  (`WatchSyncService.swift:681`) un-finished a book on any accepted watch position and one of which
  (`WatchBook.swift:118`) kept completion on a non-finishing final-word commit. The original
  completion date survives a round trip and a re-finish. `markFinishedLocally` is deleted, not
  deprecated. 412 → **415** iOS tests, 94 → **97** watchOS; combined ATTRIBUTABLE 92.43% →
  **92.45%** with a larger denominator (12911 → 13035 lines); REACH stays 100% on both platforms.
  The new journeys cross the real `PropertyListSerialization` boundary WCSession requires rather
  than passing a typed struct between peers. Written by a delegate that was killed for memory
  mid-edit and verified from the diff, not from its report — see
  [TDD-MISSION 5ay](../testing/TDD-MISSION.md#5ay-the-constraint-that-turned-a-leg-into-a-question-2026-09-07-leg-29).
- **2026-09-07** — Leg 30, Swift 6 language mode. `SWIFT_VERSION` 5.0 -> 6.0 and
  `SWIFT_STRICT_CONCURRENCY = complete` across all 14 build configurations. Strict-concurrency
  diagnostics went 4,218 -> 0 on iOS and 530 -> 0 on watchOS, with zero `@preconcurrency` and
  zero `nonisolated(unsafe)` anywhere, and no escape hatch at all in shipping code; the four
  `@unchecked Sendable` that remain are pre-existing `URLProtocol` subclasses in the test trees,
  each now carrying a written justification. B18's real scale is recorded above. The reason the
  count was so large and the fix so small is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
  isolates types nobody annotated: marking the pure-logic types `nonisolated` retired thousands
  of diagnostics at once, and is the architecturally correct answer rather than a silencer.
  **The migration's real find was B27**, a launch-time SIGTRAP that only exists once the executor
  check is switched on — the app had been calling every WatchConnectivity delegate on the wrong
  actor since the watch app shipped. Verified after the fix, by the manager rather than the
  delegate: nine gates pass, iOS 417 tests and watchOS 97 (both `** TEST SUCCEEDED **`), UI lanes
  5 and 4, combined ATTRIBUTABLE 92.49% (12061/13041) against a floor of 90, and no new crash
  report during the run. Coverage rose while the denominator grew, which is the honest direction.
  Two process notes worth keeping. The lane caught the crash and refused to certify it — the run
  reported `** TEST FAILED **` with "Early unexpected exit, operation never finished
  bootstrapping" and preserved the evidence, so no green gate was ever produced over an app that
  could not launch. And the leg stopped one step short of its own done condition because the
  brief said "run the two simulator lanes ONCE, at the end": that was written as a capacity
  guard and read, correctly, as a hard limit, so after fixing the defect the delegate would not
  re-run to prove it and said so plainly ("Combined ATTRIBUTABLE coverage is unavailable, not
  zero") rather than claiming a pass. A constraint has to carry its own reason, or it gets
  honoured to the letter in the one case where the letter is wrong. Same family as leg 29.
- **2026-09-07** — Leg 31 landed F2. Chapters were extracted, persisted and synced to the
  watch since 2026-08-31 and the iPhone never displayed them; `ChapterIndex`'s only consumer
  was `WatchSettingsLogic`. The leg added the reader sheet, the current-chapter mark, the
  RSVP chapter name and the hidden-when-empty rule, and routed chapter jumps through a new
  `ReaderSession.browse(to:)` that writes `browseWordIndex` and never the reading commit.
  Auditing that path found B28 and B29 — the bookmark and highlight pickers had been
  committing reading position all along, and a distant jump could silently no-op against an
  unmounted `LazyVStack` paragraph. Verified by the manager: nine gates, iOS 421 and watchOS
  97 tests, UI lanes 7 and 4, ATTRIBUTABLE 91.26% (12210/13379) against a floor of 90. The
  fall from 92.49% is the new view code entering the denominator, which is the metric
  working as designed rather than a regression. Release configuration builds clean and
  `strings` finds no `ChapterUITestFixture` symbol in the Release binary — checked because
  this repo once shipped a live server password from a runtime flag that was not a compile
  guard.
- **2026-10-03** — B32 fixed: watch RSVP no longer does O(book) work per word (tokenize per access, crown detents rebuilt per word). Measured 99.0% → 6.3% of a core at 1000 WPM on a 150k-word book. Reading sync with the user's own server started; see [reading-sync design notes](2026-10-03-reading-sync.md).
- **2026-10-03** — F31 client: reading anchors (fold v2, pinned to the server's shared vectors), KOSync client, debounced push of committed positions, pull as an offer in the reader, per-server toggle. Mutation controls red for the device-id, finished-cap, retry, dash-fold and drift guards.
- **2026-10-03** — F31 hardening after an independent review: offers are withdrawn by reading, by a later pull that finds nothing new, and when sync is turned off; a late or older answer cannot replace a newer offer; accepting drops the push queued before it; an unanswered probe keeps the push queued; saving a server re-probes it; a push is read back for the winner; background time ends exactly once. Ten mutation controls, all red. Joint end-to-end against CWNG passed. EPUB extraction stops reading `<head>`/`<style>`/`<script>` as text (calibre cover CSS leaked into the first words; every bundled book began `"Cover"`).
