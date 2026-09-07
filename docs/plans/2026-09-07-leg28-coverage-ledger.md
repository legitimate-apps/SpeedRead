# Leg 28 coverage ledger

OBSERVED: baseline is detached commit `41cd6a9`; final is the leg-28 working tree. Every numeric entry below comes from retained `xccov --report --json` or `--archive --file ... --json` output, not the task brief. Paths and line numbers name `SpeedRead/Connectivity/WatchSyncService.swift` (the watch copy is a symlink).

OBSERVED: xccov counts executable lines separately for functions and nested closures. The baseline iOS report has **49 missing counted lines**, but the archive has **29 distinct wholly unexecuted source lines**. Summing closure/function obligations, not counting distinct line numbers, reproduces the gate. The final iOS gap is **26 counted lines / 18 distinct lines**; watch is **57 counted lines / 32 distinct lines**. The watch baseline is **135 counted lines / 91 distinct lines**.

## Disposition of all 49 original iOS counted lines

OBSERVED: the following rows sum to 49. Baseline line numbers refer to commit `41cd6a9`. Closure entries are retained even where they share a physical line.

| Baseline function start | Missing count | Function or closure | Disposition |
|---|---:|---|---|
| 93 | 1 | `implicit closure #2 in static WatchSyncLogic.BookPayload.decode(from:inlineText:)` | Covered: `WatchSyncLogicTests.swift:230` asserts legacy count and high-water defaults. |
| 93 | 1 | `implicit closure #3 in implicit closure #2 in static WatchSyncLogic.BookPayload.decode(from:inlineText:)` | Covered: `WatchSyncLogicTests.swift:230` asserts legacy count and high-water defaults. |
| 176 | 1 | `implicit closure #1 in static WatchSyncLogic.PositionPayload.decode(from:)` | Covered: `WatchSyncLogicTests.swift:230` asserts legacy count and high-water defaults. |
| 308 | 2 | `WatchSyncService.activate()` | H |
| 393 | 1 | `implicit closure #1 in closure #1 in WatchSyncService.sendBook(id:title:author:text:wordCount:chapters:)` | L |
| 414 | 3 | `WatchSyncService.fallbackToFileTransfer(payload:)` | T |
| 421 | 1 | `implicit closure #1 in WatchSyncService.fallbackToFileTransfer(payload:)` | L |
| 549 | 1 | `WatchSyncService.sessionDidBecomeInactive(_:)` | N |
| 554 | 11 | `WatchSyncService.session(_:didFinish:error:)` | Covered: `WatchSyncServiceTests.swift:458` and `:466` enter the actual delegate with WCSessionFileTransfer subclasses and assert title, failure and delayed clearing. |
| 555 | 1 | `implicit closure #1 in WatchSyncService.session(_:didFinish:error:)` | Covered: `WatchSyncServiceTests.swift:458` and `:466` enter the actual delegate with WCSessionFileTransfer subclasses and assert title, failure and delayed clearing. |
| 556 | 8 | `closure #1 in WatchSyncService.session(_:didFinish:error:)` | Covered: `WatchSyncServiceTests.swift:458` and `:466` enter the actual delegate with WCSessionFileTransfer subclasses and assert title, failure and delayed clearing. |
| 603 | 1 | `WatchSyncService.applyIncomingPosition(_:)` | P |
| 636 | 1 | `implicit closure #1 in WatchSyncService.applyIncomingPosition(_:)` | L |
| 647 | 3 | `WatchSyncService.continueFromWatch(_:)` | P |
| 694 | 1 | `implicit closure #1 in WatchSyncService.continueFromWatch(_:)` | L |
| 701 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceiveMessage:replyHandler:)` | L |
| 717 | 8 | `WatchSyncService.session(_:didReceive:)` | Actual receipt delegate asserted on watch at `WatchSyncServiceCharacterizationTests.swift:184`, `:205`, `:247`; iOS no-effect receipt and lazy logging remain I/L below. |
| 718 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceive:)` | Actual receipt delegate asserted on watch at `WatchSyncServiceCharacterizationTests.swift:184`, `:205`, `:247`; iOS no-effect receipt and lazy logging remain I/L below. |
| 718 | 1 | `implicit closure #2 in implicit closure #1 in WatchSyncService.session(_:didReceive:)` | Actual receipt delegate asserted on watch at `WatchSyncServiceCharacterizationTests.swift:184`, `:205`, `:247`; iOS no-effect receipt and lazy logging remain I/L below. |
| 719 | 1 | `implicit closure #3 in WatchSyncService.session(_:didReceive:)` | Actual receipt delegate asserted on watch at `WatchSyncServiceCharacterizationTests.swift:184`, `:205`, `:247`; iOS no-effect receipt and lazy logging remain I/L below. |

## Every remaining counted gap, with a reason

OBSERVED: each row names the function start and its remaining counted-line obligation. Reason codes expand to the specific test not written below.

### ios: 415/441

| Current function start | Missing count | Function or closure | Reason |
|---|---:|---|---|
| 316 | 2 | `WatchSyncService.activate()` | H |
| 401 | 1 | `implicit closure #1 in closure #1 in WatchSyncService.sendBook(id:title:author:text:wordCount:chapters:)` | L |
| 422 | 3 | `WatchSyncService.fallbackToFileTransfer(payload:)` | T |
| 429 | 1 | `implicit closure #1 in WatchSyncService.fallbackToFileTransfer(payload:)` | L |
| 557 | 1 | `WatchSyncService.sessionDidBecomeInactive(_:)` | N |
| 611 | 1 | `WatchSyncService.applyIncomingPosition(_:)` | P |
| 644 | 1 | `implicit closure #1 in WatchSyncService.applyIncomingPosition(_:)` | L |
| 655 | 3 | `WatchSyncService.continueFromWatch(_:)` | P |
| 696 | 1 | `implicit closure #1 in WatchSyncService.continueFromWatch(_:)` | L |
| 703 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceiveMessage:replyHandler:)` | L |
| 719 | 8 | `WatchSyncService.session(_:didReceive:)` | I |
| 720 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceive:)` | L |
| 720 | 1 | `implicit closure #2 in implicit closure #1 in WatchSyncService.session(_:didReceive:)` | L |
| 721 | 1 | `implicit closure #3 in WatchSyncService.session(_:didReceive:)` | I |

### watch: 362/419

| Current function start | Missing count | Function or closure | Reason |
|---|---:|---|---|
| 84 | 1 | `static WatchSyncLogic.BookPayload.decode(from:inlineText:)` | S |
| 176 | 1 | `implicit closure #1 in static WatchSyncLogic.PositionPayload.decode(from:)` | S |
| 208 | 1 | `static WatchSyncLogic.shouldOfferWatchPosition(incoming:localIndex:localDate:wordCount:pendingOfferDate:)` | S |
| 228 | 3 | `static WatchSyncLogic.initialBookDeliveryRoute(isReachable:)` | S |
| 232 | 3 | `static WatchSyncLogic.bookDeliveryRouteAfterMessageFailure()` | S |
| 316 | 2 | `WatchSyncService.activate()` | H |
| 333 | 18 | `WatchSyncService.scheduleDebugPositionSyncIfRequested()` | D |
| 343 | 15 | `closure #1 in WatchSyncService.scheduleDebugPositionSyncIfRequested()` | D |
| 346 | 1 | `implicit closure #1 in closure #1 in WatchSyncService.scheduleDebugPositionSyncIfRequested()` | D |
| 522 | 1 | `WatchSyncService.persistLibrary()` | W |
| 526 | 1 | `implicit closure #1 in WatchSyncService.persistLibrary()` | L |
| 552 | 3 | `WatchSyncService.session(_:activationDidCompleteWith:error:)` | L |
| 553 | 1 | `implicit closure #1 in WatchSyncService.session(_:activationDidCompleteWith:error:)` | L |
| 553 | 1 | `implicit closure #2 in WatchSyncService.session(_:activationDidCompleteWith:error:)` | L |
| 553 | 1 | `implicit closure #3 in implicit closure #2 in WatchSyncService.session(_:activationDidCompleteWith:error:)` | L |
| 600 | 1 | `implicit closure #1 in closure #1 in WatchSyncService.session(_:didReceiveApplicationContext:)` | R |
| 703 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceiveMessage:replyHandler:)` | L |
| 720 | 1 | `implicit closure #1 in WatchSyncService.session(_:didReceive:)` | L |
| 720 | 1 | `implicit closure #2 in implicit closure #1 in WatchSyncService.session(_:didReceive:)` | L |

## Tests deliberately not written

- **H — OBSERVED:** No unsupported-hardware test: WCSession.isSupported() is a platform static with no injected control; this simulator supports it. No platform-method swizzling or invented hardware result.
- **T — OBSERVED:** No temp-file write-failure test: the generated URL and system write have no fault-injection seam. Deliberately breaking the shared temp directory or filling the disk is not a deterministic fixture. Failure-state behavior here remains unprotected.
- **L — OBSERVED:** No logger-only test: lazy diagnostic string formatting has no asserted reading, delivery, or persistence effect; enabling logs to touch it would not protect those behaviors.
- **N — OBSERVED:** No inactivity no-op test: this empty callback has no state transition or meaningful mutation to assert.
- **P — OBSERVED:** No SwiftData save-error test: the healthy in-memory ModelContext fixture has no deterministic save-failure injection seam. Success persistence is asserted; these catch/return paths remain unprotected, rather than being exercised through filesystem corruption.
- **I — OBSERVED:** No iOS file-receipt test: the library-changing receipt body is watchOS-only. On iOS the callback just reads/discards a file and logs; a state assertion would not detect deleting that read. The watch delegate has real persistence and rejection assertions.
- **D — OBSERVED:** No DEBUG position-command scheduler test: this launch-argument polling aid is compiled out of Release. Driving process-global arguments and waiting for it solely for coverage would not protect shipped behavior. Its lines remain in the existing denominator; no exemption was added.
- **S — OBSERVED:** No duplicate watch test for this remaining pure shared branch: the exact symlinked source is already asserted by iOS WatchSyncLogicTests (malformed chapters, missing high-water fallback, reconciliation and routing). These watch-target gaps remain visible; iOS coverage is not relabeled as watch execution.
- **R — OBSERVED:** No short-circuit RHS test: after the known-book guard, on the main actor, WatchLibrary.updatePosition returns true for that same book, so the `|| changed` RHS cannot affect the result. A test of the RHS alone could not catch a behavioral mutation.
- **W — OBSERVED:** No watch persistence-error logger test: the catch only logs, with no observable recovery result to assert. Storage success and rejected-file preservation are tested separately.

- **OBSERVED — redundant iOS high-water lower-bound mutant:** at source :618 and :684, migration has made the local high-water non-negative before `max(local, incoming)`. Removing only the lower bound at either of these two call sites is observationally equivalent for reachable inputs. No independent mutation-killing test was written for that equivalent mutant. The shared helper's lower bound, the offer/acceptance lower bounds, and both high-water upper bounds are asserted. This is a stated limit on the requested “any call site on either side” claim.
- **OBSERVED — redundant pre-reconciliation clamp:** the old `existingFurthestIndex` calculation at baseline :658 only populated a temporary payload passed to `reconcile`, which reads existence and timestamps (:188), not high-water. That unused calculation was deleted instead of carrying a dead clamp into the shared implementation; no line-touching test was added for it.

## Distinct unexecuted source lines

OBSERVED: these lists additionally account for each distinct physical line, including braces counted by xccov. They do not replace the closure-aware tables above.

### ios

| Current physical line | Reason |
|---|---|
| 321 | H |
| 322 | H |
| 429 | T |
| 430 | T |
| 431 | T |
| 557 | N |
| 644 | P |
| 696 | P |
| 697 | P |
| 698 | P |
| 719 | I |
| 720 | I |
| 721 | I |
| 722 | I |
| 729 | I |
| 730 | I |
| 731 | I |
| 744 | I |

### watch

| Current physical line | Reason |
|---|---|
| 115 | S |
| 216 | S |
| 228 | S |
| 229 | S |
| 230 | S |
| 232 | S |
| 233 | S |
| 234 | S |
| 321 | H |
| 322 | H |
| 341 | D |
| 342 | D |
| 343 | D |
| 344 | D |
| 345 | D |
| 346 | D |
| 347 | D |
| 348 | D |
| 349 | D |
| 350 | D |
| 351 | D |
| 352 | D |
| 353 | D |
| 354 | D |
| 355 | D |
| 356 | D |
| 357 | D |
| 358 | D |
| 526 | W |
| 552 | L |
| 553 | L |
| 554 | L |

## SpineColor

OBSERVED: iOS baseline `SpineColor.swift:27–29` was 11/14; watch baseline :31–35 plus its hash closure was 8/14. Both targets now report **14/14**, with no missing physical lines or counted obligations. `SpeedReadTests/SpineColorTests.swift:36` asserts the default/empty-palette paths; :42 asserts exact custom-palette results from independent known hashes. The watch target uses a symlink to that same test source. The pre-existing three tests now also name their mutations because they are newly run on watch. No SpineColor test was declined, and its production source was not changed.

OBSERVED evidence location: `/Volumes/Crucial X8/SpeedRead-leg28/{before,delegates}/` contains the result bundles, lane logs, report JSON, archive line JSON, and source snapshots. `coverage.log` records the actual gate results. The copying harness lives outside the repository's Scripts directory and waits for the script's lane-completion message before copying a bundle.
