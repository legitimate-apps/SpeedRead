# Reading TDD Evidence — 2026-08-29

Every factual statement below is labelled **OBSERVED** or **ASSUMED**.

## 1. Reader session and split

**OBSERVED — red-first commit:** `52ce353 test(reader): define session behavior red` added an
inert `ReaderSession` scaffold and 11 behavioral tests before the implementation commit.

Command:

```bash
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Hermetic \
  -destination 'platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
  -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' \
  -clonedSourcePackagesDirPath '/Volumes/Crucial X8/dev-caches/spm-clones' \
  -parallel-testing-enabled NO \
  -only-testing:SpeedReadTests/ReaderSessionTests
```

Selected red output:

```text
✘ Test loadsPersistedWordsAndParagraphCoordinatesOnce() recorded an issue at ReaderSessionTests.swift:14:9: Expectation failed: (session.cachedWords → []) == ["alpha", "beta", "gamma", "delta"]
✘ Test positionClampsAtFirstAndLastWord() recorded an issue at ReaderSessionTests.swift:51:9: Expectation failed: (session.clampedIndex(2) → 0) == 2
✘ Test tapCommitsClampedPositionAndRequestsAUniqueFlash() recorded an issue at ReaderSessionTests.swift:79:9: Expectation failed: (first.commit → ReadingPositionCommit(index: 0, timestamp: 1970-01-01 00:01:40 +0000, didSave: false)) == (ReadingPositionCommit(index: 2, timestamp: firstDate, didSave: true) → ReadingPositionCommit(index: 2, timestamp: 1970-01-01 00:01:40 +0000, didSave: true))
✘ Suite "Reader session" failed after 0.027 seconds with 29 issues.
✘ Test run with 11 tests in 1 suite failed after 0.027 seconds with 29 issues.
```

**OBSERVED — red-run caveat:** the test process completed and emitted the failed test-count line,
but that invocation then stopped making progress in `xcodebuild` finalization. It was terminated
after the evidence above, so the shell exit was 143 rather than Xcode's normal test-failure 65.

**OBSERVED — green implementation:** `878cc8a feat(reader): implement tested session behavior`
implemented the session. `c2ac3d2 refactor(reader): make view present session state` then wired the
view and split themes and sheets without changing the tested behavior.

Green output:

```text
✔ Test loadsPersistedWordsAndParagraphCoordinatesOnce() passed after 0.001 seconds.
✔ Test emptyBookLoadsAsAnEmptySession() passed after 0.001 seconds.
✔ Test singleWordBookClampsEveryPositionToZero() passed after 0.001 seconds.
✔ Test positionClampsAtFirstAndLastWord() passed after 0.001 seconds.
✔ Test tapCommitsClampedPositionAndRequestsAUniqueFlash() passed after 0.001 seconds.
✔ Test clearingAnOldFlashDoesNotCancelANewerTap() passed after 0.001 seconds.
✔ Test saveFailureIsReportedWithoutDroppingThePositionOrSync() passed after 0.001 seconds.
✔ Test emptyBookCommitUsesTheOnlyValidCoordinate() passed after 0.001 seconds.
✔ Test initialAndRSVPDismissScrollsUseTheCurrentClampedPosition() passed after 0.006 seconds.
✔ Test scrollAnchorIdentityPreservesTheUniversalWordIndex() passed after 0.001 seconds.
✔ Test themesCycleInDisplayOrderAndRecoverFromInvalidStorage() passed after 0.001 seconds.
✔ Suite "Reader session" passed after 0.021 seconds.
✔ Test run with 11 tests in 1 suite passed after 0.021 seconds.
** TEST SUCCEEDED **
```

**OBSERVED:** `ReaderView.swift` is 349 source lines after the split; it was 542 source lines before
this leg. `ReaderTheme.swift`, `ReaderSheets.swift`, `ReaderSession.swift`, and `ReaderConfig.swift`
are separate files.

## 2. RSVP presentation logic, B4, and B15

**OBSERVED — red-first commit:** `3b2261b test(rsvp): reproduce scrub gesture defects red`
mechanically preserved the existing scrub arithmetic and independent tap routing in a testable
session before either fix.

Command:

```bash
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Hermetic \
  -destination 'platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
  -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' \
  -clonedSourcePackagesDirPath '/Volumes/Crucial X8/dev-caches/spm-clones' \
  -parallel-testing-enabled NO \
  -only-testing:SpeedReadTests/RSVPPresentationSessionTests
```

Required B4 and B15 red output:

```text
◇ Test "B4: a new gesture cannot inherit velocity from the previous gesture" started.
✘ Test "B4: a new gesture cannot inherit velocity from the previous gesture" recorded an issue at RSVPPresentationSessionTests.swift:32:9: Expectation failed: (second.wordDelta → 6) == 2
✘ Test "B4: a new gesture cannot inherit velocity from the previous gesture" recorded an issue at RSVPPresentationSessionTests.swift:33:9: Expectation failed: (second.velocity → 1600.0015258803614) == (0 → 0.0)
✘ Test "B4: a new gesture cannot inherit velocity from the previous gesture" recorded an issue at RSVPPresentationSessionTests.swift:34:9: Expectation failed: (second.effectivePointsPerWord → 2.499997615814209) == (ReaderConfig.RSVP.basePointsPerWord → 8.0)
✘ Test "B4: a new gesture cannot inherit velocity from the previous gesture" failed after 0.003 seconds with 3 issues.
◇ Test "B15: a quick swipe is scrub-only and never routed as a tap" started.
✘ Test "B15: a quick swipe is scrub-only and never routed as a tap" recorded an issue at RSVPPresentationSessionTests.swift:48:9: Expectation failed: (session.endGesture() → .togglePlayback) == .scrubbed
✘ Test "B15: a quick swipe is scrub-only and never routed as a tap" failed after 0.002 seconds with 1 issue.
✘ Test run with 6 tests in 1 suite failed after 0.008 seconds with 6 issues.
** TEST FAILED **
```

**OBSERVED — green fix:** `f063ad6 fix(rsvp): reset and route scrub gestures` resets the time
baseline at a gesture boundary and classifies the completed movement before routing play/pause.

Required B4 and B15 green output:

```text
◇ Test "B4: a new gesture cannot inherit velocity from the previous gesture" started.
✔ Test "B4: a new gesture cannot inherit velocity from the previous gesture" passed after 0.001 seconds.
◇ Test "B15: a quick swipe is scrub-only and never routed as a tap" started.
✔ Test "B15: a quick swipe is scrub-only and never routed as a tap" passed after 0.001 seconds.
✔ Test run with 6 tests in 1 suite passed after 0.003 seconds.
** TEST SUCCEEDED **
```

**OBSERVED — additional red/green lifecycle:** `4f81fdd` and `5d6f07d` committed the RSVP load,
close, disappear, bookmark, highlight, feedback, and duplicate-dismiss tests while red.
`179608e` implemented them. A later function-coverage audit added zero-time, within-gesture
acceleration, and maximum-velocity-cap cases in `804c53b`. The final focused output before that
audit was:

```text
✔ Test loadsPersistedTokensAtTheSavedPositionAndSpeed() passed after 0.001 seconds.
✔ Test emptyStreamLoadsWithoutAnInvalidIndex() passed after 0.001 seconds.
✔ Test closeSnapshotsBeforePauseAndPersistsTheVisibleIndex() passed after 0.001 seconds.
✔ Test disappearCommitsLoadedPositionBeforeStopping() passed after 0.001 seconds.
✔ Test closeIsNotPersistedAgainWhenDisappearFollows() passed after 0.001 seconds.
✔ Test disappearDoesNotPersistAnUnloadedEngine() passed after 0.001 seconds.
✔ Test bookmarkDraftClampsAndUsesTheVisibleWordWindow() passed after 0.001 seconds.
✔ Test highlightCanBeCompletedInEitherDirection() passed after 0.001 seconds.
✔ Test feedbackTokensAreUniqueAndOldTasksCannotClearNewFeedback() passed after 0.001 seconds.
✔ Test "B4: a new gesture cannot inherit velocity from the previous gesture" passed after 0.001 seconds.
✔ Test "B15: a quick swipe is scrub-only and never routed as a tap" passed after 0.001 seconds.
✔ Test stationaryTouchRoutesToPlayPause() passed after 0.001 seconds.
✔ Test scrubDirectionAndBoundsUseWordCoordinates() passed after 0.001 seconds.
✔ Test subThresholdMovementDoesNotSeek() passed after 0.001 seconds.
✔ Test playingAndEmptyStreamsCannotSeek() passed after 0.001 seconds.
✔ Test run with 15 tests in 1 suite passed after 0.007 seconds.
** TEST SUCCEEDED **
```

**OBSERVED:** the RSVP word surface now has one `DragGesture(minimumDistance: 0)`. A movement below
`ReaderConfig.RSVP.scrubActivationDistance` routes play/pause; a movement at or above it is consumed
as scrub. There is no independent `onTapGesture` left in `RSVPView.swift`.

**OBSERVED:** B4's failing second sample inherited approximately 1,600 points/second and sought six
words. Resetting `lastDragTime` made the identical second gesture seek two words at zero inherited
velocity. This confirms the supplied stale-time hypothesis and refutes the roadmap's statement that
resetting `lastDragX` was itself the defect.

## 3. Configuration and documented invariants

**OBSERVED:** `ReaderConfig` contains the reader typography ranges, transition durations, padding,
RSVP WPM step, scrub activation distance, velocity scaling, haptic interval, control-panel geometry,
and feedback timing. Tests reference those values in both gesture arithmetic and configuration
coherence assertions.

**OBSERVED — characterization, not red-first TDD:** commit `7b901f4 test(reading): pin documented
invariants` extracted the existing token-cache operation without changing its semantics and added
direct tests for the three documented invariants. Command:

```bash
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -testPlan Hermetic \
  -destination 'platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
  -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' \
  -clonedSourcePackagesDirPath '/Volumes/Crucial X8/dev-caches/spm-clones' \
  -parallel-testing-enabled NO \
  -only-testing:SpeedReadTests/BookTests \
  -only-testing:SpeedReadTests/TextFileExtractorTests \
  -only-testing:SpeedReadTests/RSVPDismissPersistenceTests
```

Output:

```text
✔ Test ensureTokensCachedIsIdempotentForAnAlreadyMigratedBook() passed after 0.001 seconds.
✔ Test legacyTokenCacheMigrationUsesTheCanonicalTokenizer() passed after 0.001 seconds.
✔ Test tokenCacheHelperDoesNotRecomputePersistedTokens() passed after 0.001 seconds.
✔ Test snapshotIndexAndPauseAtomicallyPausesAPlayingEngineWithoutChangingItsIndex() passed after 0.001 seconds.
✔ Test negativeControlStopDoesZeroTheVisibleIndex() passed after 0.001 seconds.
✔ Test detectTitleAlwaysTrustsAnExplicitGutenbergHeader() passed after 0.001 seconds.
✔ Test run with 31 tests in 3 suites passed after 0.067 seconds.
** TEST SUCCEEDED **
```

**OBSERVED:** `rg -n 'DispatchQueue\.main\.asyncAfter|onTapGesture'
SpeedRead/Views/ReaderView.swift SpeedRead/Views/RSVPView.swift` produced no matches. All five named
`asyncAfter` violations are absent.

## 4. Residual SwiftUI bodies and final verification

**OBSERVED — characterization, not red-first TDD:** commit `db8f9af test(reading): exercise residual
SwiftUI bodies` names and hosts `ReaderView`, `RSVPView`, all three reader sheets, their injected
sessions, and their real SwiftData environment. It asserts lifecycle state and nonuniform rendered
pixels through UIKit/Core Graphics; it does not merely instantiate a body with no assertion.

Focused output:

```text
✔ Test readerBodyRunsItsSessionLoadTaskWhenHosted() passed after 0.149 seconds.
✔ Test rsvpBodyLoadsItsEngineAtThePersistedWordWhenHosted() passed after 0.148 seconds.
✔ Test behaviorConstantsStayInternallyCoherent() passed after 0.008 seconds.
✔ Test readerSheetsRenderNonemptyNamedStates() passed after 0.199 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.507 seconds.
** TEST SUCCEEDED **
```

**OBSERVED — final bare-scheme hermetic run:** no `-testPlan` and no `-only-testing` were passed.

```bash
xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead \
  -destination 'platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
  -derivedDataPath '/Volumes/Crucial X8/DerivedData/speedread-tests' \
  -clonedSourcePackagesDirPath '/Volumes/Crucial X8/dev-caches/spm-clones' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/SpeedRead-Leg2-Hermetic-Final2.xcresult
```

```text
✔ Test run with 182 tests in 23 suites passed after 1.254 seconds.
** TEST SUCCEEDED **
```

**OBSERVED — final coverage instrument and watch build/test:** the watch destination was leased
through `sim-lease`, the script ran its xcodebuild invocations serially, and the lease was released
afterwards.

**OBSERVED — watch simulator recovery:** two newly leased watch simulators built the app but then
failed launch with `Unknown application display identifier`; both `xcodebuild` processes also
stopped making progress after emitting that error and were terminated. On the second lease,
`simctl install` installed the already-built `Debug-watchsimulator/SpeedReadWatch Watch App.app`,
and `simctl listapps` positively showed `com.legitimateapps.SpeedRead.watchkitapp`. A
`test-without-building` positive control then ran 4/4 tests, and the complete coverage command below
subsequently passed on that same leased destination. No source or project setting changed as part of
that simulator-state recovery.

```bash
SPEEDREAD_IOS_DESTINATION='platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
SPEEDREAD_WATCH_DESTINATION='platform=watchOS Simulator,id=DC0D2814-E93E-46E2-94E0-676616D5EA78' \
SPEEDREAD_DERIVED_DATA_PATH='/Volumes/Crucial X8/DerivedData/speedread-tests' \
SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH='/Volumes/Crucial X8/dev-caches/spm-clones' \
Scripts/coverage.sh 0
```

Verbatim output:

```text
Running iOS hermetic unit lane...
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
✔ Test run with 182 tests in 23 suites passed after 1.587 seconds.
** TEST SUCCEEDED **
Running watchOS hermetic unit lane...
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
✔ Test run with 4 tests in 1 suite passed after 0.005 seconds.
** TEST SUCCEEDED **

Coverage exclusions: none

SpeedRead.app overall: 42.91% (3700/8623)
Coverage   Covered/Executable  File
     0.00%        0/16        SpeedRead/Services/OPDSCoverCache.swift
     0.00%        0/49        SpeedRead/Services/SampleBookLoader.swift
     0.00%        0/144       SpeedRead/Views/BookSpineView.swift
     0.00%        0/285       SpeedRead/Views/BookmarkListView.swift
     0.00%        0/193       SpeedRead/Views/BookshelfRowView.swift
     0.00%        0/336       SpeedRead/Views/HighlightListView.swift
     0.00%        0/140       SpeedRead/Views/LibraryLayoutPreviews.swift
     0.00%        0/820       SpeedRead/Views/LibraryView.swift
     0.00%        0/651       SpeedRead/Views/Server/BrowseServerView.swift
     0.00%        0/143       SpeedRead/Views/Server/OPDSEntryRowView.swift
     0.00%        0/376       SpeedRead/Views/Server/RemoteBookDetailView.swift
     0.00%        0/396       SpeedRead/Views/Server/ServerEditView.swift
     0.00%        0/247       SpeedRead/Views/Server/ServerListView.swift
     0.00%        0/168       SpeedRead/Views/SettingsView.swift
     0.00%        0/192       SpeedRead/Views/ThemePickerView.swift
    38.04%       97/255       SpeedRead/Connectivity/WatchSyncService.swift
    44.74%       34/76        SpeedRead/Views/LibraryLayoutMetrics.swift
    45.95%       17/37        SpeedRead/Views/ReaderTheme.swift
    71.43%      100/140       SpeedRead/Services/OPDSClient.swift
    71.96%      195/271       SpeedRead/Extraction/EPUBExtractor.swift
    74.84%      354/473       SpeedRead/Views/ReaderSheets.swift
    76.47%       39/51        SpeedRead/Services/DocumentImporter.swift
    78.31%       65/83        SpeedRead/Views/ReaderWordFlow.swift
    78.57%       11/14        SpeedRead/Theme/SpineColor.swift
    85.82%      678/790       SpeedRead/Views/ReaderView.swift
    86.39%      762/882       SpeedRead/Views/RSVPView.swift
    87.72%       50/57        SpeedRead/Services/KeychainStore.swift
    92.42%       61/66        SpeedRead/Extraction/TextFileExtractor.swift
    94.06%      269/286       SpeedRead/Views/OnboardingView.swift
    94.48%      137/145       SpeedRead/Engine/RSVPEngine.swift
    95.83%       23/24        SpeedRead/Extraction/RTFExtractor.swift
    96.15%       25/26        SpeedRead/ContentView.swift
    96.40%      214/222       SpeedRead/Services/OPDSAtomParser.swift
   100.00%       48/48        SpeedRead/Engine/ORPCalculator.swift
   100.00%       29/29        SpeedRead/Engine/WordTimer.swift
   100.00%       19/19        SpeedRead/Extraction/PDFExtractor.swift
   100.00%       68/68        SpeedRead/Models/Book.swift
   100.00%       13/13        SpeedRead/Models/Bookmark.swift
   100.00%       14/14        SpeedRead/Models/Highlight.swift
   100.00%       16/16        SpeedRead/Models/OPDSServer.swift
   100.00%       15/15        SpeedRead/SpeedReadApp.swift
   100.00%       12/12        SpeedRead/Theme/Theme.swift
   100.00%        9/9         SpeedRead/Theme/ThemeManager.swift
   100.00%      133/133       SpeedRead/Views/RSVPPresentationSession.swift
   100.00%       97/97        SpeedRead/Views/RSVPWordView.swift
   100.00%       96/96        SpeedRead/Views/ReaderSession.swift

SpeedReadWatch Watch App.app overall: 7.06% (136/1927)
Coverage   Covered/Executable  File
     0.00%        0/48        SpeedReadWatch Watch App/Shared/ORPCalculator.swift
     0.00%        0/145       SpeedReadWatch Watch App/Shared/RSVPEngine.swift
     0.00%        0/97        SpeedReadWatch Watch App/Shared/RSVPWordView.swift
     0.00%        0/5         SpeedReadWatch Watch App/Shared/SpineColor.swift
     0.00%        0/29        SpeedReadWatch Watch App/Shared/WordTimer.swift
     0.00%        0/342       SpeedReadWatch Watch App/Views/WatchBookDetailView.swift
     0.00%        0/330       SpeedReadWatch Watch App/Views/WatchRSVPView.swift
     0.00%        0/101       SpeedReadWatch Watch App/Views/WatchSettingsView.swift
    13.76%       41/298       SpeedReadWatch Watch App/Shared/WatchSyncService.swift
    14.16%       64/452       SpeedReadWatch Watch App/Views/WatchLibraryView.swift
    25.00%        3/12        SpeedReadWatch Watch App/Shared/Theme.swift
    25.93%       14/54        SpeedReadWatch Watch App/Shared/WatchBook.swift
   100.00%       14/14        SpeedReadWatch Watch App/SpeedReadWatchApp.swift

Combined shipping code: 36.36% (3836/10550)
Required threshold: 0%
PASS: combined line coverage meets 0%
```

**OBSERVED — affected-file delta from the supplied baseline:** `ReaderView.swift` moved from
0/1262 (0.00%) to 678/790 (85.82%); `RSVPView.swift` moved from 0/897 (0.00%) to 762/882 (86.39%).
New extracted types report `ReaderSession.swift` 96/96 (100.00%) and
`RSVPPresentationSession.swift` 133/133 (100.00%). The split `ReaderSheets.swift` reports 354/473
(74.84%). Overall iOS shipping coverage moved from 1486/8362 (17.77%) to 3700/8623 (42.91%).

**OBSERVED:** `ReadingViewRenderingTests.swift` directly names `ReaderView`, `RSVPView`,
`ReaderSettingsSheet`, `ReaderBookmarkPicker`, and `ReaderHighlightPicker`. The affected SwiftUI
coverage therefore has real assertions attributable to a test that names each rendered type; it is
not launch-only ghost coverage.

## Deliberately not performed

**OBSERVED:** no third-party package or dependency was added. No version, release posture, or
`docs/plans/*` status column was changed. No push was performed.

**OBSERVED:** the `ios-visual-verifier` skill was inspected because the gesture surface changed, but
its hard model lock requires Claude Opus 4.6 Max and explicitly requires aborting under any other
model. This Codex session therefore did not run the separate screenshot/director-signoff workflow.
The Apple-SDK-only hosted rendering tests above were run and are not presented as a substitute for
human visual approval.

**ASSUMED:** physical-device gesture feel is unchanged apart from the intended B4/B15 corrections;
no physical-device session was run.
