# Coverage baseline

Measured on **2026-08-29** with Xcode 26.6, an iPhone 17 Pro simulator on iOS 26.5, and an
Apple Watch Series 11 (46mm) simulator on watchOS 26.5.

No source file is excluded. The combined number is weighted by executable lines across the two
shipping binaries: `(iOS covered + watch covered) / (iOS executable + watch executable)`. Shared
source is counted in each binary in which it ships.

| Shipping target | Line coverage |
|---|---:|
| `SpeedRead.app` | **17.77%** (1486/8362) |
| `SpeedReadWatch Watch App.app` | **7.06%** (136/1927) |
| Combined shipping code | **15.76%** (1622/10289) |

## Reproduce

From the repository root, the instrument creates the same two serial test lanes with its standard
named simulator destinations:

```bash
Scripts/coverage.sh 15
```

The exact command used for this measurement pinned the already-leased destinations and caches:

```bash
SPEEDREAD_IOS_DESTINATION='platform=iOS Simulator,id=9202766C-CD78-4DD4-9F18-E538F62D30C4' \
SPEEDREAD_WATCH_DESTINATION='platform=watchOS Simulator,id=95ED9C04-DDD5-4F96-953C-15EA1BA22CCD' \
SPEEDREAD_DERIVED_DATA_PATH='/Volumes/Crucial X8/DerivedData/speedread-tests' \
SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH='/Volumes/Crucial X8/dev-caches/spm-clones' \
Scripts/coverage.sh 15
```

The measured test summaries were:

```text
✔ Test run with 144 tests in 20 suites passed after 0.776 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.005 seconds.
```

## Verbatim coverage report

```text
Coverage exclusions: none

SpeedRead.app overall: 17.77% (1486/8362)
Coverage   Covered/Executable  File
     0.00%        0/16        SpeedRead/Services/OPDSCoverCache.swift
     0.00%        0/49        SpeedRead/Services/SampleBookLoader.swift
     0.00%        0/144       SpeedRead/Views/BookSpineView.swift
     0.00%        0/285       SpeedRead/Views/BookmarkListView.swift
     0.00%        0/193       SpeedRead/Views/BookshelfRowView.swift
     0.00%        0/336       SpeedRead/Views/HighlightListView.swift
     0.00%        0/140       SpeedRead/Views/LibraryLayoutPreviews.swift
     0.00%        0/820       SpeedRead/Views/LibraryView.swift
     0.00%        0/897       SpeedRead/Views/RSVPView.swift
     0.00%        0/97        SpeedRead/Views/RSVPWordView.swift
     0.00%        0/1262      SpeedRead/Views/ReaderView.swift
     0.00%        0/651       SpeedRead/Views/Server/BrowseServerView.swift
     0.00%        0/143       SpeedRead/Views/Server/OPDSEntryRowView.swift
     0.00%        0/376       SpeedRead/Views/Server/RemoteBookDetailView.swift
     0.00%        0/396       SpeedRead/Views/Server/ServerEditView.swift
     0.00%        0/247       SpeedRead/Views/Server/ServerListView.swift
     0.00%        0/168       SpeedRead/Views/SettingsView.swift
     0.00%        0/192       SpeedRead/Views/ThemePickerView.swift
    34.12%       87/255       SpeedRead/Connectivity/WatchSyncService.swift
    34.94%       29/83        SpeedRead/Views/ReaderWordFlow.swift
    44.74%       34/76        SpeedRead/Views/LibraryLayoutMetrics.swift
    71.43%      100/140       SpeedRead/Services/OPDSClient.swift
    71.96%      195/271       SpeedRead/Extraction/EPUBExtractor.swift
    75.00%        9/12        SpeedRead/Theme/Theme.swift
    76.47%       39/51        SpeedRead/Services/DocumentImporter.swift
    78.57%       11/14        SpeedRead/Theme/SpineColor.swift
    86.21%      125/145       SpeedRead/Engine/RSVPEngine.swift
    87.72%       50/57        SpeedRead/Services/KeychainStore.swift
    89.83%       53/59        SpeedRead/Models/Book.swift
    92.42%       61/66        SpeedRead/Extraction/TextFileExtractor.swift
    94.06%      269/286       SpeedRead/Views/OnboardingView.swift
    95.83%       23/24        SpeedRead/Extraction/RTFExtractor.swift
    96.15%       25/26        SpeedRead/ContentView.swift
    96.40%      214/222       SpeedRead/Services/OPDSAtomParser.swift
    97.92%       47/48        SpeedRead/Engine/ORPCalculator.swift
   100.00%       29/29        SpeedRead/Engine/WordTimer.swift
   100.00%       19/19        SpeedRead/Extraction/PDFExtractor.swift
   100.00%       13/13        SpeedRead/Models/Bookmark.swift
   100.00%       14/14        SpeedRead/Models/Highlight.swift
   100.00%       16/16        SpeedRead/Models/OPDSServer.swift
   100.00%       15/15        SpeedRead/SpeedReadApp.swift
   100.00%        9/9         SpeedRead/Theme/ThemeManager.swift

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

Combined shipping code: 15.76% (1622/10289)
Required threshold: 15%
PASS: combined line coverage meets 15%
```

The default iOS lane also instruments the embedded watch app, but an iOS test destination cannot
execute watch code and therefore reports that binary at 0%. `Scripts/coverage.sh` replaces that
non-measurement with the watch target's coverage from `WatchHermetic.xctestplan`; it never merges
the iOS lane's 0% watch record into the measured watch total.
