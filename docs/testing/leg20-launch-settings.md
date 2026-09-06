# Leg 20 — launch and settings surfaces

## Current handoff — manager-directed revision

OBSERVED: the pageSelection seam is removed. All 25 focused unit tests now pass, including
pairwise rendering of the three independent onboarding pages and completion persistence.
The new UI test successfully taps Next → Next → Open Your Library and observes the library.
However, its additional disposable-preferences-home assertion fails: the expected plist is
absent. Therefore the one focused invocation exits 65, and OnboardingView's test work remains
**NOT DONE** until that UI-test isolation fixture is corrected. The other four target files
retain passing focused behavioral tests. No further build was run under the one-run limit.

OBSERVED: the prior failed unit-transition result and prior measured coverage below are
historical. They do not describe the revised content-rendering test. The final revision result
and exact UI steps are recorded at the end of this document. No final combined attributable
figure or full UI-lane result is claimed. No commit was made.

## Earlier evidence (superseded where stated)

OBSERVED: the operator narrowed the final handoff after two host low-memory interruptions.
Do not run the full coverage or UI lanes in this agent process; the manager will run them
once it exits. No commit is authorized. Evidence is retained at `/tmp/speedread-leg20`.

OBSERVED: four target files have passing focused behavioral tests. OnboardingView remains
unfinished: its page/control/persistence assertions passed, but two pixel-transition assertions
failed in the single final focused run. The failing assertions are retained, not weakened.
The post-red full-coverage attempt was interrupted before producing results; no after-gate
number is claimed. No coverage/UI process remained when this turn resumed.

OBSERVED baseline (`Scripts/coverage.sh 84`, before edits, exit 0):

```text
     0.00%        0/168       SpeedRead/Views/SettingsView.swift
     0.00%        0/192       SpeedRead/Views/ThemePickerView.swift
    93.33%       42/45        SpeedRead/ContentView.swift
    94.06%      269/286       SpeedRead/Views/OnboardingView.swift
   100.00%       15/15        SpeedRead/SpeedReadApp.swift
   100.00%        9/9         SpeedRead/Theme/ThemeManager.swift
Combined ATTRIBUTABLE: 85.88% (8308/9674)
Required ATTRIBUTABLE threshold: 84%
PASS: combined attributable coverage meets 84%
```

OBSERVED: the first five files were named by no test at baseline. Their launch-path lines
were GHOST, not attributable. ThemeManager was already attributable. Test/helper/document
files have no shipping-target xccov row; the production WatchSyncService file is unchanged.

## Behavioral red observed

OBSERVED: `python3 /tmp/speedread-leg20/red-run.py` ran the six-test suite with the
intentional mutations described above. xcodebuild exited 65; all source backups were restored.
The following are unaltered selected output lines (large pixel-array diagnostics omitted):

```text
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:26:9: Expectation failed: (state.page → 0) == 1
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:27:9: Expectation failed: try #require(subviews(host.view, as: UIPageControl.self).first).currentPage == 1
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:33:9: Expectation failed: (state.page → 0) == 2
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:34:9: Expectation failed: try #require(subviews(host.view, as: UIPageControl.self).first).currentPage == 2
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:38:9: Expectation failed: (storage.defaults → <NSUserDefaults: 0x1156ec6f0>).bool(forKey: "hasCompletedOnboarding")
✘ Test contentGateTracksCompletionInBothDirectionsAndClaimsReviewOnce() recorded an issue at LaunchSurfaceTests.swift:81:9: Expectation failed: (storage.defaults.integer(forKey: "reviewPromptLaunchCount") → 4) == 3
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:115:13: Expectation failed: (manager.currentTheme.id → "classic") == (theme.id → "midnight")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:116:13: Expectation failed: (storage.defaults.string(forKey: "selectedThemeId") → "classic") == (theme.id → "midnight")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:117:13: Expectation failed: (ThemeManager(defaults: storage.defaults).currentTheme.id → "classic") == (theme.id → "midnight")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:115:13: Expectation failed: (manager.currentTheme.id → "classic") == (theme.id → "modern")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:116:13: Expectation failed: (storage.defaults.string(forKey: "selectedThemeId") → "classic") == (theme.id → "modern")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:117:13: Expectation failed: (ThemeManager(defaults: storage.defaults).currentTheme.id → "classic") == (theme.id → "modern")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:115:13: Expectation failed: (manager.currentTheme.id → "classic") == (theme.id → "vintage")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:116:13: Expectation failed: (storage.defaults.string(forKey: "selectedThemeId") → "classic") == (theme.id → "vintage")
✘ Test themeButtonsPersistSelectionAndUpdatePicker() recorded an issue at LaunchSurfaceTests.swift:117:13: Expectation failed: (ThemeManager(defaults: storage.defaults).currentTheme.id → "classic") == (theme.id → "vintage")
↳ Settings must display the selected theme
↳ Settings must display the selected theme
↳ Settings must display the selected theme
↳ Settings must display the selected theme
✘ Test appSchemaContainsEveryPersistedModel() recorded an issue at LaunchSurfaceTests.swift:146:9: Expectation failed: (names → ["Bookmark", "Highlight", "Book"]) == ["Book", "Bookmark", "Highlight", "OPDSServer"]
✘ Test run with 6 tests in 1 suite failed after 12.929 seconds with 26 issues.
** TEST FAILED **
```

OBSERVED: all Button lookup and image/precondition assertions passed. Five tests detected
their deliberate behavior regression; the pre-third-launch test passed. This is red-first
characterization of existing behavior, not a claim that these intentional bugs existed before
this leg. Compiler failures, reflection-probe failures, and the launch failure are excluded.

## Final focused verification (narrowed handoff)

OBSERVED: `Scripts/honesty-gates.sh > /tmp/speedread-leg20/honesty-final.log 2>&1`
exited 0; all six gates passed. One focused build/test invocation completed (exit 65), using
one existing leased simulator and `-jobs 1`. It uses the single selector
`-only-testing:SpeedReadTests`, with command-line skips for unchanged suites. These are
local focused-test selection, not modifications or exemptions to any gate or test plan.
The selected suites contain 25 tests: LaunchSurfaceTests (6), ThemeTests (7), and
WatchSyncServiceTests (12). The latter changed only to share its fake connection helper.

OBSERVED exact command:

```sh
/usr/bin/xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Hermetic -destination 'platform=iOS Simulator,id=65FAB8AD-65E7-4407-BFEC-B4EF5E526417' -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' -jobs 1 -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:SpeedReadTests -skip-testing:SpeedReadTests/AnnotationListLogicTests -skip-testing:SpeedReadTests/AnnotationListViewRenderingTests -skip-testing:SpeedReadTests/BookTests -skip-testing:SpeedReadTests/BookmarkTests -skip-testing:SpeedReadTests/BrowseServerLogicTests -skip-testing:SpeedReadTests/BundledSampleBookTests -skip-testing:SpeedReadTests/ChapterIndexTests -skip-testing:SpeedReadTests/ChapterTokenIdentityTests -skip-testing:SpeedReadTests/DocumentImporterDataTests -skip-testing:SpeedReadTests/EPUBExtractorTests -skip-testing:SpeedReadTests/HighlightTests -skip-testing:SpeedReadTests/LibraryLayoutMetricsTests -skip-testing:SpeedReadTests/LibraryViewRenderingTests -skip-testing:SpeedReadTests/NetworkIsolationGuardTests -skip-testing:SpeedReadTests/OPDSAtomParserTests -skip-testing:SpeedReadTests/OPDSBrowseLogicTests -skip-testing:SpeedReadTests/OPDSClientTests -skip-testing:SpeedReadTests/OPDSCoverCacheTests -skip-testing:SpeedReadTests/OPDSFormatAvailabilityLogicTests -skip-testing:SpeedReadTests/OPDSServerFormLogicTests -skip-testing:SpeedReadTests/ORPCalculatorTests -skip-testing:SpeedReadTests/PDFExtractorTests -skip-testing:SpeedReadTests/RSVPDismissPersistenceTests -skip-testing:SpeedReadTests/RSVPEngineTests -skip-testing:SpeedReadTests/RSVPIntegrationTests -skip-testing:SpeedReadTests/RSVPPresentationSessionTests -skip-testing:SpeedReadTests/RSVPWordFitTests -skip-testing:SpeedReadTests/RTFExtractorTests -skip-testing:SpeedReadTests/ReaderParagraphTests -skip-testing:SpeedReadTests/ReaderSessionTests -skip-testing:SpeedReadTests/ReadingViewRenderingTests -skip-testing:SpeedReadTests/RemoteBookDetailLogicTests -skip-testing:SpeedReadTests/ReviewPromptLogicTests -skip-testing:SpeedReadTests/SampleBookLoaderTests -skip-testing:SpeedReadTests/ServerEditLogicTests -skip-testing:SpeedReadTests/ServerListLogicTests -skip-testing:SpeedReadTests/SpineColorTests -skip-testing:SpeedReadTests/SupportedFormatTests -skip-testing:SpeedReadTests/TextFileExtractorTests -skip-testing:SpeedReadTests/WatchSyncLogicTests -skip-testing:SpeedReadTests/WordTimerTests -resultBundlePath /tmp/speedread-leg20/focused.xcresult
```

OBSERVED evidence paths: `focused.log`, `focused.xcresult`, and `focused-exit.txt` beneath
`/tmp/speedread-leg20`. No full lane will be started under the narrowed instruction.

## Final focused outcome and handoff

OBSERVED: the single focused run built successfully and executed exactly 25 tests in three
suites. **24 passed; the onboarding test failed with two issues.** There was no additional
build or test invocation after this result, in accordance with the operator's one-run limit.
No full coverage or UI lane was run after the narrowed instruction.

OBSERVED output:

```text
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:28:9: Expectation failed: (explanation → Rendered image (28304 spatial RGB samples)) != (welcome → Rendered image (28304 spatial RGB samples))
✘ Test onboardingButtonsAdvanceAndCompleteOnlyOnTheLastPage() recorded an issue at LaunchSurfaceTests.swift:35:9: Expectation failed: (ready → Rendered image (28304 spatial RGB samples)) != (explanation → Rendered image (28304 spatial RGB samples))
✔ Test contentGateTracksCompletionInBothDirectionsAndClaimsReviewOnce() passed after 3.637 seconds.
✔ Test contentDoesNotRequestReviewBeforeThirdLaunch() passed after 0.535 seconds.
✔ Test themeButtonsPersistSelectionAndUpdatePicker() passed after 2.777 seconds.
✔ Test settingsDisplaysEachSelectedTheme() passed after 2.665 seconds.
✔ Test appSchemaContainsEveryPersistedModel() passed after 0.038 seconds.
✘ Test run with 25 tests in 3 suites failed after 11.819 seconds with 2 issues.
** TEST FAILED **
```

OBSERVED: the onboarding action bridge executed the actual Next and completion closures.
PageState advanced to 1 and 2, the hosted UIPageControl reported those indices, completion
remained false until the last button, and that button persisted true in the isolated suite.
However, the `UIView.layer.render` samples were identical at all three stages. This contradicts
the asserted visible page transition. It is **not** established whether paging failed visually
or this capture method returned stale/incomplete page content. A page-control update alone
cannot settle that question. No end-to-end onboarding claim is made.

ASSUMED / next investigation: inspect the hosted paging collection's visible content and
consider a UIKit hierarchy snapshot for paged SwiftUI content. This has not been tried and
must not be treated as a verified fix. Preserve both image-transition assertions until the
cause is demonstrated. The explicit one-run constraint prevents another exploratory build
in this agent turn; the manager must resolve this before expecting the full gate to pass.

OBSERVED per-file xccov from the **failing focused run**, not a combined lane measurement:

```sh
xcrun xccov view --report --json /tmp/speedread-leg20/focused.xcresult > /tmp/speedread-leg20/focused-coverage.json
```

```text
   100.00%       15/15        SpeedRead/SpeedReadApp.swift
   100.00%       51/51        SpeedRead/ContentView.swift
    98.21%      165/168       SpeedRead/Views/SettingsView.swift
    99.48%      191/192       SpeedRead/Views/ThemePickerView.swift
   100.00%       10/10        SpeedRead/Theme/ThemeManager.swift
    99.65%      287/288       SpeedRead/Views/OnboardingView.swift
```

OBSERVED: all six measured production files exceed 90% in this focused run. These percentages
do not establish passing behavior: OnboardingView is the explicit counterexample. No after
combined-attributable figure is available, and no increase above 85.88% is claimed.

OBSERVED remaining uncovered executable locations in the focused archive:

- `SpeedRead/Views/OnboardingView.swift:7`: the stored page initializer is reported zero.
- `SpeedRead/Views/ThemePickerView.swift:26`: Done dismissal closure, not invoked by these tests.
- `SpeedRead/Views/SettingsView.swift:40`: Done dismissal closure, not invoked.
- `SpeedRead/Views/SettingsView.swift:49` and `:50`: missing-version/build fallback expressions;
  the test host supplies both Info.plist values.
- ContentView, SpeedReadApp, and ThemeManager have no uncovered executable lines in this run.

OBSERVED: archive detail is retained in `onboarding-lines.txt`, `picker-lines.txt`, and
`settings-lines.txt` under `/tmp/speedread-leg20`. For mixed covered/uncovered source lines,
xccov's zero-count column ranges identify the closures/fallbacks listed above.

## What is authored and what remains

| Target | Focused status | Assertions / implementation reference |
| --- | --- | --- |
| OnboardingView | **NOT DONE** — two image-transition assertions fail | `LaunchSurfaceTests.swift:10`; real button closures, pages, persistence; rendering discrepancy at lines 28 and 35 |
| ContentView | **DONE as authored; focused tests pass** | `LaunchSurfaceTests.swift:41` and `:85`; route in both directions, real onAppear, review count/request, process reuse, sync activation |
| ThemePickerView | **DONE as authored; focused test passes** | `LaunchSurfaceTests.swift:103`; all four real selection closures, current theme, persistence/reload, display changes and restoration |
| SettingsView | **DONE as authored; focused test passes** | `LaunchSurfaceTests.swift:124`; each theme changes the rendered settings surface, Classic restores it |
| SpeedReadApp | **DONE as authored; focused test passes** | `LaunchSurfaceTests.swift:143`; exact schema entities plus save/fetch of all four model types |

OBSERVED: `SpeedReadApp.swift:10` owns the schema type list used by its scene at line 20.
The schema assertion is genuine and detects the omitted OPDSServer; it does not merely
instantiate `@main` or claim launch lines as proof. `ContentView.swift:16` injects defaults,
a process gate, and a review callback while retaining its decision/wiring in the view.
`ThemeManager.swift:13` and `:25` inject the persistence store. Existing ThemeTests now uses
isolated suites; no test in this change writes the three named keys to standard defaults.
`IsolatedDefaults.swift:4` gives every test a UUID domain and removes that domain at teardown.
These seams work independently of any test-plan environment flag.

OBSERVED limitation: Button actions are extracted from real view fragments using a test-only
Mirror/closure-ABI bridge (`LaunchSurfaceTests.swift:174`). This ran successfully in red and in
the focused run on iOS 26.5. It depends on SwiftUI's current stored closure representation and
fails when that representation changes. It is not proof of UIKit gesture dispatch, physical
taps, swipe paging, or toolbar dismissal. No new UI test was added; the required UI lane is
still the manager's pending work. Production behavior was not relocated into other files;
no dependency, gate floor, gate exemption, or test plan changed.

OBSERVED final cheap verification:

```sh
Scripts/honesty-gates.sh > /tmp/speedread-leg20/honesty-handoff.log 2>&1
git diff --check
```

```text
test files: 67   tests: 413   assertion-free: 0   sleep-then-nothing: 0
lane audit passed: 5 test targets, 6 plans, every target in a plan and every plan in a lane
shared-source audit passed: 9 filenames in both trees, all single-source
PASS: executed-test parser control -- 12 checks, expected counts all matched
PASS: strip_comments self-test -- 9 cases, both directions asserted
PASS: all honesty gates
```

OBSERVED: both commands exited 0 (diff check emitted no output). The six gates include
actionlint. The working tree contains only production/test changes and this report; scratch
scripts, raw logs, and result bundles are outside it. No commit was made.

Pending manager work: resolve the onboarding capture/transition discrepancy; then run
`Scripts/coverage.sh 84` and `Scripts/ui-lanes.sh` after the agent process exits. The full
coverage comparison must beat 85.88% (8308/9674), not just meet the 84% floor. Existing leased
iPhone destination: `65FAB8AD-65E7-4407-BFEC-B4EF5E526417`; watch destination:
`96053777-0825-4572-BD73-520FA9365667`. Warm build directory:
`/Volumes/Crucial X8/DerivedData/speedread-tests` (reacquire through dd-lease before building).

## Manager-directed revision — page content vs UIKit paging

OBSERVED: the manager identified the stale page captures as a `layer.render` limitation across
TabView's UIKit child containers and directed a design change. The prior failed focused result
above is historical, not the final implementation. The pageSelection/selection seam is removed;
OnboardingView uses its original private @State and TabView binding. Only the three page
properties remain internal.

OBSERVED authored changes: the unit test renders the three page properties independently,
asserts all three pairwise content differences, and retains completion persistence. A new
OnboardingUITests test launches without any onboarding override, taps Next twice and Open Your
Library, asserts each page and the library, and relaunches to assert completion is remembered.
It uses a disposable CFFIXED_USER_HOME and asserts the completion plist was written there;
this isolation mechanism is awaiting the focused run. It adds no production launch hook.

OBSERVED lane wiring: SpeedReadUITests is a filesystem-synchronized target; UI.xctestplan names
it, and Scripts/ui-lanes.sh:160 invokes that plan. TDD-MISSION §5af–§5ah were read before writing
the UI test. The full coverage and UI lanes remain manager-owned after this process exits.

OBSERVED revision checkpoint: all six honesty gates passed before the focused build
(`/tmp/speedread-leg20/revision-honesty.log`). One focused xcodebuild invocation is running.
To execute both affected unit suites and the new UI suite in that single invocation, its driver
temporarily adds the unit target to UI.xctestplan and restores the exact original in `finally`.
Coverage remains disabled for this mixed focused run; it is not attributable coverage evidence.
If interrupted before restoration, restore UI.xctestplan from
`/tmp/speedread-leg20/UI-plan-backup.txt`. No permanent plan or gate change is intended.

Exact focused command (run by `/tmp/speedread-leg20/revision-focused.py`):

```sh
/usr/bin/xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan UI -destination 'platform=iOS Simulator,id=65FAB8AD-65E7-4407-BFEC-B4EF5E526417' -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' -jobs 1 -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:SpeedReadTests/LaunchSurfaceTests -only-testing:SpeedReadTests/ThemeTests -only-testing:SpeedReadTests/WatchSyncServiceTests -only-testing:SpeedReadUITests/OnboardingUITests -resultBundlePath /tmp/speedread-leg20/revision-focused.xcresult
```

## Revision result — unit content green, real paging observed, isolation fixture unresolved

OBSERVED: the single revision-focused invocation exited 65. It compiled the app and both test
targets. All 25 selected unit tests passed; the one UI test failed only after completing the
requested user flow, while checking the disposable preferences plist. The original UI plan
was restored byte-for-byte (`cmp UI.xctestplan /tmp/speedread-leg20/UI-plan-backup.txt`, exit 0).
The plan still includes SpeedReadUITests, and the lane still invokes UI.xctestplan.

OBSERVED selected UI automation output (verbatim event lines):

```text
    t =     5.32s Tap "Next" Button
    t =     5.83s Waiting 5.0s for "One word at a time" StaticText to exist
    t =     6.91s Tap "Next" Button
    t =     7.31s Waiting 5.0s for "Your shelf is ready" StaticText to exist
    t =     8.39s Tap "Open Your Library" Button
    t =    10.58s Waiting 8.0s for "Your Library" NavigationBar to exist
    t =    11.63s         Checking existence of `"Your Library" NavigationBar`
    t =    11.66s Terminate com.legitimateapps.SpeedRead:18517
Test Case '-[SpeedReadUITests.OnboardingUITests testNewReaderPagesThroughOnboardingAndOpensLibrary]' failed (12.996 seconds).
✔ Test run with 25 tests in 3 suites passed after 11.364 seconds.
** TEST FAILED **
```

OBSERVED failure at `SpeedReadUITests/OnboardingUITests.swift:36`: Data(contentsOf:) throws
NSCocoaErrorDomain Code=260 because `com.legitimateapps.SpeedRead.plist` does not exist at the
expected disposable-home path. This is an isolation-fixture failure, **not behavioral red for
onboarding**. The page text, button hittability, and library assertions preceding it passed.
The relaunch assertion after that read was not executed and is unverified.

OBSERVED: `CFFIXED_USER_HOME` did not produce the asserted preferences artifact. It is not
established where CFPreferences wrote the completion state; do not claim this UI test is
hermetic. Its defer terminated the app and removed the disposable directory, but cannot
prove restoration of the app's normal defaults. The original unit defaults-isolation tests
remain green and unchanged. The UI fixture must be corrected before running the complete
lane against any persistent/user-owned simulator; use a disposable leased simulator meanwhile.
No production shim was added to implement the UI fixture.

OBSERVED final cheap checks (both exit 0):

```sh
Scripts/honesty-gates.sh > /tmp/speedread-leg20/revision-handoff-honesty.log 2>&1
git diff --check
```

```text
test files: 68   tests: 414   assertion-free: 0   sleep-then-nothing: 0
lane audit passed: 5 test targets, 6 plans, every target in a plan and every plan in a lane
shared-source audit passed: 9 filenames in both trees, all single-source
PASS: executed-test parser control -- 12 checks, expected counts all matched
PASS: strip_comments self-test -- 9 cases, both directions asserted
PASS: all honesty gates
```

OBSERVED final status: ContentView, ThemePickerView, SettingsView, and SpeedReadApp have passing
focused tests. OnboardingView now has passing unit content/completion tests and an observed
successful real UI path, but its UI test remains failing on the extra isolation fixture.
There are no half-written methods or placeholder assertions; the failing isolation assertion
is retained rather than suppressed. The narrowed green condition has **not** been achieved.

OBSERVED: no new coverage was collected in this mixed run (UI plan coverage disabled), and
neither full lane was invoked in this revision. Earlier per-file rows remain in this report,
explicitly historical. The manager still owns final coverage (>85.88%, floor 84) and both UI
lanes after this process exits, once the isolated UI fixture is resolved.

OBSERVED cleanup: the iPhone lease `65FAB8AD-65E7-4407-BFEC-B4EF5E526417` was released/deleted
at handoff, removing this run's app data, including any regular-defaults completion write.
Do not reuse that old destination from historical commands. The warm DerivedData lease was
released. Future verification should acquire a fresh simulator and reacquire DerivedData.
