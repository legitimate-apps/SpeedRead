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
- **2026-10-03** — EPUB markup is stripped in linear time. The element and tag regular expressions were quadratic on openings that never close: 8,000 of them took 5 s and 12.5 s (measured), from a file anyone can import. They are now scans, checked against the old expressions on 20,000 random inputs with 0 differences. A positive control confirmed the only intended change shows up: a self-closed `<script … />` no longer swallows the text before the next `</script>`.
- **2026-10-04** — Live phone↔watch handoff (operator's ask: "whichever was moved by the human user last, that's where we resume on both devices"). The place (`browseWordIndex` + new `browseDate`) now syncs both ways, last-write-wins, moved by every interaction; the watch→phone offer banner is gone. While one device plays, the other shows "Reading on iPhone / Apple Watch" on that book (and a library label), cannot progress it, and takes over on "Read here". Found and fixed on the way: a place never moved (every book from before this change) would have accepted any stale incoming place, and the watch's settings button paused without ending the run, which would have left the phone locked behind the card. Mutation controls red for both, and for the phone-side fallback. The paired-simulator run found a third: the reader's "Read here" opened RSVP paused, because the autoplay flag was a separate `@State` read only inside the `fullScreenCover` closure and reached RSVP stale; RSVP is now presented by an item that carries the flag. After it, both directions were observed end to end (watch plays → phone card; phone "Read here" → watch yields in 233 ms at the phone's word; phone pause → watch card clears on the same word; and the mirror, 390 ms). The watch card is now opaque (the word bled through its text at 94%). An independent review then found four more, each fixed behind a test that its mutation turns red: a device that had yielded committed the other device's word when it closed (a yield must never commit), so it rolled the still-reading device back; a heartbeat delivered after its own pause re-raised the card for six seconds (a per-book release floor now refuses it); chapter, bookmark and highlight jumps stayed enabled behind the card and were overwritten within a second (disabled now); and every place the phone scrubbed rewrote the watch's whole library, up to four times a second (a place alone now persists at most every 5 s, with a trailing write). Deferred, both judged improbable: places compare across two device clocks, so a takeover within the skew margin can be refused as stale, and the expiry timer does not re-arm if the wall clock steps backward mid-window. Also deferred: the reader header's percentage follows the reading marker, so it lags the card's live percentage until the reading device pauses. Design: [live handoff](../superpowers/specs/2026-10-04-live-handoff-design.md).
- **2026-10-04** — RSVP long tokens and bounded passages (operator, from TestFlight 1.4 (8) screenshots: a URL "looks weird and bad", and a lone `***` flashed as a word). The URL was drawn at a fraction of its size off to the right because its pivot came from "www" alone (the first letter run) while the other 27 characters had to fit the right half. Following the operator's choices (keep the pivot centered; do not break non-words): a token past 13 characters that is not a word (URL, address, ISBN: anything with digits or `/ . @ _` inside) pivots on its middle, so it sits centered at the largest size the width allows, and is held in proportion to its length (characters / 10 beats, never under the 1.3 of a long word). A long word of letters is shown as balanced hyphenated pieces (Spritz's rule; breaks at dashes first, then the system hyphenator, never leaving a stub), each with its own pivot and beat, all on one word index so positions and sync never see them. New: passages bounded by punctuation (quotes, including quotations that reopen at each paragraph; parentheses and brackets; `*`/`**`/`***` and `_` runs; dash pairs within one sentence) are found by a single stack pass over the book's text (`TextEnclosures`, no model and no regex: 96,000 words in 0.39 s on the simulator in a Debug build, off the main actor) and their marks are drawn faintly either side of the upper guide tick, outermost pair outside. It fails toward showing nothing: an unclosed mark bounds nothing, inline bounds end at their paragraph and at a cap (60 words for star/underscore runs, 80 for brackets, 30 for dashes), and a scan whose word count differs from the book's is discarded. A lone mark that opens or closes a passage (`***`) gets no beat in playback. Nine mutation controls, each red against the test written for it. A background security review after build 9 flagged that a single enormous token (junk or embedded data in a broken or hostile file) could freeze RSVP: splitting was quadratic on the main actor, a non-word's hold had no ceiling, and the scanner's stack had no depth limit. Now a run past 64 letters is shown whole rather than split, the hold stops at 4 beats, and the scanner ignores openers past 16 deep (and a dash pair inside one word bounds nothing); each bound has a mutation control that turns its test red. These land after build 9. Deferred: on the watch a long URL is legible but small (a 29-character URL draws at about 10 pt); the indicator is not announced to VoiceOver.
- **2026-10-04** — RSVP scrub you can see, and a new icon. Operator, from a screen recording of 1.4 (9): make the swipe "more clear what is going on … more visually engaging", show words "transitioning from right to left for the next word". Asked which way forward should be, they kept swipe-left = next (the page-turn convention). Before, a drag swapped the word in place at 8 pt a word with nothing on screen saying which way it went (the recording shows 41 words passing in about a second). Now, while dragging, the words either side are drawn dimly on the same line (`RSVPWordStrip`) and the line follows the finger: the next word arrives from the right, the shown word is always the nearest to the guides (rounded, not truncated), the red pivot fades out as its word leaves and hands over at the halfway point, and on release the line glides back to the nearest word. A gold caption under the word says "12 words back ‹" / "41 words ahead ›", and a hint ("Swipe to move word by word · Tap to play") shows until the first drag (`rsvpHasScrubbed`). A slow drag now moves a word per 14 pt so single words can be picked out; acceleration reaches the old top speed (about 1.3 pt a word) at about 3,200 pt/s. VoiceOver can now move a word with swipe up/down and play with a double-tap. Nothing moves during playback, and the watch is unchanged (it scrubs with the crown). The geometry is pure (`RSVPWordStripLayout`, tested on both platforms, including that a word changing hands moves nothing). Mutation controls red: truncating instead of rounding, reversing the shift, and shifting to a neighbor's edge instead of its pivot. App icon: the "Pivot Seal" (a gold R between the RSVP guide marks, pressed into oxblood wax, on parchment), made with fal image models by a design subagent from the operator's wax-seal idea, with dark (transparent) and tinted variants, which the catalog had left empty, and the watch icon.
- **2026-10-05** — RSVP scrub rebuilt to move like text, with haptics. Operator, from a screen recording of 1.4 (10): it "feels very bad", wanted haptics, lower or more human speed sensitivity, and asked why "the interaction only starts a few second later". Diagnosis from the recording at 30 fps: for 270 ms the word flipped five times (and first one word the wrong way, from finger jitter past 7 pt) before any neighbor appeared, because the strip faded in only after the word had already changed; and the line ran about six times faster than the finger, since a word cost 14 pt of drag while words sit about 80–170 pt apart on screen. A Luna 6.0 blind tester on build 10 agreed: 45 pt did nothing, 52 pt jumped four words, a 250 pt flick went 89 words (control 1/5, flick distance 1/5). Now the line moves exactly with the finger: the RSVP font is monospaced, so `RSVPScrubTrack` knows each neighbor's on-screen pivot distance from character counts (checked against the font as rendered), and `RSVPScrubPosition` hands the guides to whichever pivot is nearest. Measured on the simulator, a 50 pt swipe moved the line 50.3 pt. The strip appears at the drag's first 5 pt, before any word changes. On release, `RSVPScrubGlide` carries a flick on for as far as the finger would go in 0.35 s at its release speed, leaving at that speed (ease-out cubic, no lurch) and landing exactly on a word; a slow release settles in 0.2 s, and a touch during a glide catches the line (it never starts playback). Haptics: a selection tick for every word that reaches the guides, gliding included, and one rigid knock at either end of the book (previously one light tap every tenth word). The motion runs on a display link, so the fade-out no longer depends on an implicit animation. Usability round 2 (two Luna 6.0 testers, blind, on the new build; reports in `~/Dispatcher/briefs/speedread-scrub-usability/`) rated it obviousness 4 and 4, immediacy 3 and 2, control 3 and 3, moving text 2 and 2, flick distance 4 and 2 (build 10: 2, 2, 1, 2, 1). Both said the word barely tracked a slow drag. That is the input injector, not the app: in a 30 fps capture `axe swipe` delivered four move events across a two-second swipe, and each moved the line exactly the finger's step, so only a real finger can judge continuity. Round 2 also surfaced a real bug, reproduced on the simulator: three identical slow swipes moved +2, +61, +3 words. Logging found the cause in `RSVPScrubGlide.nearestPivot`. A release at 339 pt/s, aimed about one word back, ran 34 words back, because the landing search compared the unsigned distance to the target, and a short word just past the target looked far away again. It stepped on to the 60-word bound. The unit tests had used one repeated word, whose equal spacing cannot show that; the new property test sweeps targets across words of mixed length (the old search fails it at 28 targets). Three further changes came from the round. The release speed is now measured by the session over the finger's last 50 ms, never over less than a frame and capped at 5,000 pt/s, instead of taken from `DragGesture`'s velocity; this is a bound and makes the speed testable, not the cause of the runaway. Dragging past either end, the line now gives (up to 60 pt, stiffening) and springs back, so a back-drag at word 1 is visible and not only a haptic. And the first-run hint names the direction: "Drag right to go back, left to go ahead · Tap to play". After the fix, on the simulator, 16 alternating 250 pt flicks moved 2–8 words each and slow swipes 1–2, with no runaway. Round 3 (the careful-reader persona again, on that build) rated obviousness 3, immediacy 2, control 2, moving text 2, flick distance 2. It landed exactly with one-word drags. It found equal flicks moving 2 and 5 words, and five too far for a reread. Its frame samples missed the strip that rounds 2a and 2b and the 30 fps capture all show. The flick spread follows axe's uneven event timing (release speeds of 900–1,500 pt/s logged for identical swipes). Even so, two of the three testers since the rebuild, and the operator, asked for gentler flicks, so the projection is now 0.25 s (from 0.35) and the cap 4,000 pt/s. Deferred: keeping the hint visible while paused after the first drag (round 3's ask), since a permanent hint is clutter once the gesture is learned. A real-phone check of haptics and drag continuity is still owed.
- **2026-11-03** — PDFs on iOS 27 no longer gain junk words, and CI splits between two hosts (operator's brief, from BUILD COMPUTE's findings). PDFKit on OS 27 writes U+FFFC into page text for some PDFs, and each one became a word that RSVP and the reader show as a dashed "OBJ" box. OBSERVED on a real iPhone on iOS 27.0.1 with apps built on the 26.2 and 27.0 SDKs (190 tokens against 187, text byte-identical to the iOS 27 simulator), and not on iPadOS 26.6.1 with the same two apps, so the OS decides. 3 of 91 text PDFs sampled locally had them. `AttachmentMarkers` removes them in the extractor. A book imported on iOS 27 before this keeps them in its stored words, since removing them would shift its positions. Separately, a test-only crash is fixed: hosted views outlived their SwiftData container, which only a slower host exposed. Pushes now run on the MacBook (run 41763441144, `mbp-build-speedread`, iOS 26.3.1), and iOS 27 runs on the Studio before a release (run 41763444528, `speedread-mac`, iOS 27.0).
- **2026-11-08** — A file with no text is refused with a reason, and import errors read as sentences (operator's pick for 1.4 (13): "Show an error, in build 13"). A scanned or image-only PDF imported as a 0-word book with no error; `DocumentImporter` now throws `ExtractionError.noReadableText(format)` when the book would have no words, counted by the same tokenizer the reader uses, and saves nothing. Found next to it: `ExtractionError` was never a `LocalizedError`, so the library's alert said "The operation couldn't be completed. (SpeedRead.ExtractionError error N.)" for every bad file, including the damaged EPUBs 1.3's What's New said were "rejected with a clear message", and a server download showed the enum's own spelling. Every case now has a reader-facing sentence, and the parser's detail stays in the value for tests and logs. For server downloads, a textless file names the same book's other readable format on the server (EPUB first), selects it, and the next tap downloads it (`RemoteBookDetailLogic.downloadFailure`). TXT and RTF files with no text throw the same case instead of `parsingFailed`. Tests: `ExtractionErrorMessageTests`, two importer tests, a library-alert test and a scripted-server download-then-retry test; 101 tests in the 9 affected suites pass on the iOS 27 simulator.
- **2026-11-08** — A highlight or bookmark belongs to the device that made it, as CWNG decides (operator: "make sure that it has high qualty integration with CWNG"). A live Integration lane against a fresh CWNG v4.1.63 rig failed 1 of 7: CWNG #2586 (first released in v4.1.48) lets an identified device change only its own rows and legacy ones with no device, and answers any other edit with `unchanged`, so a note edited on a second device was silently never stored. SpeedRead decided ownership per app (`isTextQuoteSource`). Now one predicate, `AnnotationSyncLogic.isOwned(source:originDevice:deviceID:)`, decides note edits, deletes (another device's row is only forgotten here) and pushes (only owned rows, always with this device's id). `Bookmark` gains `syncOriginDevice`, filled from the server for rows pulled before it existed. A foreign highlight's note opens read-only, with where to change it. Seven new tests; five mutants each caught. The live lane then passed 7 of 7 on iOS 27.0 (`~/.cache/speedread-b13/run-160648/`, not kept in the repo).
- **2026-11-08** — CWNG client round from an audit of SpeedRead against CWNG v4.1.63 (operator: "make sure that it has high qualty integration with CWNG"). Position calls now send `X-CWNG-Device-ID`/`-Name` and a `timestamp` (the book's `lastReadDate`), so CWNG judges by latest-write instead of furthest, and going back in a book now syncs. CWNG #2586 keeps a newly identified device's place private, so the server editor shows a one-time "turn on Share my place" note when `share_place_gates` is on. The operator chose this trade. Annotation calls deliberately carry no device header: CWNG would then serve only that device's highlights. Also: "C++" searches as typed; a failed next page keeps its link and can be retried; refused passwords (401/403) are told apart from servers without sync; a device removed in CWNG stops pushing and says so; OPDS errors read as sentences (429 included); series show on rows and the detail page; `filename*=` is preferred; books stream to disk; covers persist on disk, downscaled, ignoring `no-store`. Hermetic iOS 723 and watch 170 passed, attributable coverage 90.93%. The live Integration plan passed 8/8 on iOS 27.0 after Share my place was turned on for the two test devices; the first run's one failure was that expected gate (`~/.cache/speedread-cwng-fixes/live.md`). Deferred: download resume (untestable under the stub harness), and Test Connection succeeding with a wrong password on a guest-browsing server (CWNG #2844). Nine CWNG issues from the audit are #2841–#2849; SpeedRead adopts #2841 (share state in auth), #2842 (Basic write route, giving "Mark finished") and #2843 (PUT says kept) as they ship.
- **2026-11-08** — The Share my place note also shows once in the reader, for a book from a server that keeps this device's place private (operator's pick: most readers never open server settings). Dismissing it there dismisses it for that server. Test: `theReaderShowsTheSameNoteForABookFromThatServerAndDismissesItForTheServer`. Rendered and checked in parchment, sepia and night.
