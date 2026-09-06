# Leg 19 — annotation rendering coverage

OBSERVED 2026-09-06: both views now have named rendering tests. Combined attributable coverage
rose from **85.12% (7663/9003)** to **85.88% (8308/9674)**, an increase of **0.763605 percentage
points**. The tests add 671 attributable executable lines and cover 645 of them. This is
red-first **characterization of existing markup**, not a new behavior implemented through TDD.

OBSERVED: the only deliverables are `SpeedReadTests/AnnotationListViewRenderingTests.swift` and
this report. Both production view files, the coverage script, dependencies, and gate exemptions
are unchanged. No commit was made.

## Scope and assertions

OBSERVED: `BookmarkListView.swift:18` and `HighlightListView.swift:18` each branch between empty
and populated. Neither file contains search, a sort selector, or a navigation destination.
Their rows seek the supplied engine and dismiss instead of pushing a destination.

OBSERVED: tests follow the existing `LibraryViewRenderingTests` UIKit window-hosting pattern,
with an in-memory SwiftData container. The helper at
`SpeedReadTests/AnnotationListViewRenderingTests.swift:154` hosts a 390 × 844 window; the helper at
line 166 samples pixels with their positions preserved, excluding system navigation/status chrome.
Each rendering is followed by state assertions. No screenshot files or third-party packages are used.

OBSERVED: the bookmark test at line 12 and highlight test at line 72 cover:

- Empty, populated with three annotations, singleton after deleting two annotations, and empty
  again after deleting the last annotation. The final empty render must equal the initial one.
- Unsorted relationship insertion and tied word positions with different creation dates.
  Reordering the relationship must leave the displayed render unchanged. Logic values assert the
  expected IDs, one-based positions/ranges, and highlight word spans.
- Changed passage text must visibly alter its row. Changed bookmark position or highlight range
  must alter the singleton render; the corresponding logic values are also asserted.
- Changed creation date must alter the rendered row.
- Deletion selection uses one ordered snapshot, verifies the intended IDs, deletes real models
  through the in-memory context, saves, checks the surviving relationship, and eventually checks
  that the persisted annotation count is zero.

## Valid red, then green

OBSERVED: for the red run, only `Text(bookmark.previewText)` and
`Text(highlight.highlightedText)` were temporarily replaced with `Text("Fixed passage mutation")`.
Both tests reached their changed-text assertions. There were exactly two issues, one per test;
all other assertions passed. The production text expressions were then restored.

OBSERVED command (exit 65):

```sh
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Hermetic \
  -destination "platform=iOS Simulator,id=$(cat /tmp/speedread-leg19/ios-udid)" \
  -derivedDataPath "$(cat /tmp/speedread-leg19/dd)" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:SpeedReadTests/AnnotationListViewRenderingTests \
  -resultBundlePath /tmp/speedread-leg19/red-assertions.xcresult \
  > /tmp/speedread-leg19/red-assertions.log 2>&1
```

OBSERVED output (line numbers are from the test revision at the time of red):

```text
✘ Test bookmarksRenderEmptySortedUpdatedAndDeletedStates() recorded an issue at AnnotationListViewRenderingTests.swift:40:9: Expectation failed: previewChanged
↳ Changing bookmark preview text must change the rendered row
✘ Test highlightsRenderEmptySortedUpdatedAndDeletedStates() recorded an issue at AnnotationListViewRenderingTests.swift:94:9: Expectation failed: passageChanged
↳ Changing highlighted text must change the rendered row
✘ Test run with 2 tests in 1 suite failed after 4.091 seconds with 2 issues.
** TEST FAILED **
```

OBSERVED: the same command after restoring the view expressions, with output paths changed to
`green.xcresult` and `green.log`, exited 0:

```text
✔ Test run with 2 tests in 1 suite passed after 4.051 seconds.
** TEST SUCCEEDED **
```

OBSERVED invalid attempts, excluded from evidence: the initial run failed compilation because
nested `Fixture` needed `@MainActor`; it proved nothing about rendering. A later action-only
selector ran zero tests despite Xcode success; it was discarded. Rerunning the whole suite with
that exploratory action test did execute three tests, but forwarding UIKit's `didSelectItemAt`
delegate callback did not invoke the SwiftUI button (engine stayed at word 0 instead of 40).
That exploratory test was removed, not relaxed into a passing claim.

## Full gate, before and after

OBSERVED: the following command was run before adding tests (`baseline.log`) and on the final test
revision (`after.log`). Both invocations exited 0. The iOS lease was
`4DE458C1-F9C5-4984-A480-C6A20191D650`; the watch lease was
`51A77E40-EEBB-4283-9A26-DF25AC134039`. DerivedData came from
`dd-lease path --project speedread --purpose tests`.

```sh
SPEEDREAD_IOS_DESTINATION="platform=iOS Simulator,id=$(cat /tmp/speedread-leg19/ios-udid)" \
SPEEDREAD_WATCH_DESTINATION="platform=watchOS Simulator,id=$(cat /tmp/speedread-leg19/watch-udid)" \
SPEEDREAD_DERIVED_DATA_PATH="$(cat /tmp/speedread-leg19/dd)" \
Scripts/coverage.sh 82 > /tmp/speedread-leg19/after.log 2>&1
```

OBSERVED baseline xccov rows and combined metrics, as printed by `coverage.sh`:

```text
     0.00%        0/298       SpeedRead/Views/BookmarkListView.swift
     0.00%        0/373       SpeedRead/Views/HighlightListView.swift
Combined HEADLINE:     63.02% (8233/13064)
Combined ATTRIBUTABLE: 85.12% (7663/9003)
Combined REACH:        68.91% (9003/13064 executable lines)
Required ATTRIBUTABLE threshold: 82%
PASS: combined attributable coverage meets 82%
```

OBSERVED final output:

```text
  iOS hermetic unit lane: 324 tests executed
✔ Test run with 324 tests in 43 suites passed after 18.232 seconds.
** TEST SUCCEEDED **
  watchOS hermetic unit lane: 70 tests executed
✔ Test run with 70 tests in 17 suites passed after 0.219 seconds.
** TEST SUCCEEDED **
    95.64%      285/298       SpeedRead/Views/BookmarkListView.swift
    96.51%      360/373       SpeedRead/Views/HighlightListView.swift
Combined HEADLINE:     67.96% (8878/13064)
Combined ATTRIBUTABLE: 85.88% (8308/9674)
Combined REACH:        74.05% (9674/13064 executable lines)
Required ATTRIBUTABLE threshold: 82%
PASS: combined attributable coverage meets 82%
```

OBSERVED: `Scripts/honesty-gates.sh > /tmp/speedread-leg19/honesty-after.log 2>&1` exited 0.
All six gates passed: actionlint, assertion audit, lane audit, shared-source audit, executed-test
parser control, and coverage-classifier control. Relevant output:

```text
test files: 65   tests: 407   assertion-free: 0   sleep-then-nothing: 0
PASS: executed-test parser control -- 12 checks, expected counts all matched
PASS: strip_comments self-test -- 9 cases, both directions asserted
PASS: all honesty gates
```

OBSERVED: the measured result is 3.879677 points above the unchanged 82% floor. It supports an
integer floor of 85%, not 86%, on this run. Baseline already supported 85%; this leg increased
its margin from 0.116072 to 0.879677 points. Raising the floor remains the manager's decision.

## Remaining gap — not claimed as end-to-end coverage

OBSERVED in xccov: each view retains **13 uncovered executable lines**, all in callbacks:

| File | Row seek/dismiss | Swipe deletion | Done dismissal |
| --- | --- | --- | --- |
| `SpeedRead/Views/BookmarkListView.swift` | lines 35–38 (4) | lines 55–62 (8) | line 72 (1) |
| `SpeedRead/Views/HighlightListView.swift` | lines 35–38 (4) | lines 64–71 (8) | line 81 (1) |

OBSERVED: the new tests exercise persisted deletion and its rendered effects directly; they do
not invoke `.onDelete`, tap rows, or press Done. Rendering a callback does not execute it.
These callbacks are reachable through user interaction; they are **not** labeled unreachable.
Both files exceed the requested approximately 85% coverage threshold, but neither is 100% covered.

ASSUMED / unverified by this leg: real row tap → engine seek → sheet dismissal, swipe gesture →
`.onDelete` → persistence, and Done → dismissal. No end-to-end claim is made for those paths, for
sheet detent changes, or for other device sizes and accessibility configurations.

OBSERVED: local full logs, the red/green result bundles, final iOS xccov JSON, and per-line xccov
archives were retained outside the working tree under `/tmp/speedread-leg19`. The new test file
and this report are the only working-tree additions; no scratch artifacts are in the repo.
