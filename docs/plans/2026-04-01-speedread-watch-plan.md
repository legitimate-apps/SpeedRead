# SpeedRead Apple Watch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an Apple Watch companion app with RSVP-only speed reading, synced via WatchConnectivity.

**Architecture:** Shared code (Book model, ORP calculator, WordTimer, RSVPEngine) between iOS and watchOS targets via target membership. WatchConnectivityManager using ObservableObject (required by WCSessionDelegate's NSObject inheritance). Watch has its own local SwiftData store — book text transferred via transferFile(), reading position synced via updateApplicationContext().

**Tech Stack:** SwiftUI, SwiftData, WatchConnectivity, Digital Crown API

**Key constraints:**
- `.fullScreenCover` is NOT available on watchOS — use sheets or NavigationStack
- WCSessionDelegate requires NSObject subclass — must use ObservableObject, not @Observable
- `.focusable()` MUST come BEFORE `.digitalCrownRotation()` in modifier chain
- Each device has its own SwiftData store — no shared container across devices
- watchOS 10.0 minimum deployment target

---

## Task W1: Add watchOS Target to Xcode Project

This must be done manually in Xcode or via xcodebuild. The user will need to add the target.

**Step 1:** User adds Watch App target in Xcode:
- File > New > Target > watchOS > "App"
- Product Name: `SpeedReadWatch`
- Bundle ID: `com.legitimateapps.SpeedRead.watchkitapp`
- SwiftUI lifecycle, Swift language
- Deployment target: watchOS 10.0

**Step 2:** Create the watch app directory structure:
```
SpeedReadWatch/
├── SpeedReadWatchApp.swift
├── ContentView.swift
└── Assets.xcassets/
```

**Step 3:** Verify build for watchOS:
```bash
xcodebuild -project SpeedRead.xcodeproj -scheme SpeedReadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build
```

**Step 4:** Commit

---

## Task W2: WatchConnectivity Manager (Shared)

Create the connectivity service used by both iPhone and Watch.

**Files:**
- Create: `SpeedRead/Connectivity/WatchSyncService.swift`

**Must use ObservableObject** (not @Observable) because WCSessionDelegate requires NSObject.

```swift
//  WatchSyncService.swift
import Foundation
import WatchConnectivity

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    @Published var lastReceivedBookTitle: String?
    @Published var lastReceivedBookText: String?
    @Published var lastReceivedBookAuthor: String?
    @Published var lastReceivedPosition: Int = 0
    @Published var isWatchReachable: Bool = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send book to Watch (iPhone side)

    #if os(iOS)
    func sendBook(title: String, author: String, text: String) {
        guard WCSession.default.activationState == .activated else { return }

        // Write text to temp file for transferFile
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try? text.write(to: tempURL, atomically: true, encoding: .utf8)

        let metadata: [String: Any] = [
            "title": title,
            "author": author
        ]
        WCSession.default.transferFile(tempURL, metadata: metadata)
    }
    #endif

    // MARK: - Sync reading position (bidirectional)

    func syncReadingPosition(bookTitle: String, wordIndex: Int) {
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([
            "bookTitle": bookTitle,
            "wordIndex": wordIndex,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let title = applicationContext["bookTitle"] as? String {
                self.lastReceivedBookTitle = title
            }
            if let index = applicationContext["wordIndex"] as? Int {
                self.lastReceivedPosition = index
            }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let title = metadata["title"] as? String
        let author = metadata["author"] as? String

        if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
            DispatchQueue.main.async {
                self.lastReceivedBookTitle = title
                self.lastReceivedBookAuthor = author
                self.lastReceivedBookText = text
            }
        }
    }
}
```

**Step 1:** Write failing test for WatchSyncService

```swift
import Testing
import Foundation
@testable import SpeedRead

@Suite("Watch Sync Service Tests")
struct WatchSyncServiceTests {
    @Test @MainActor func sharedInstanceExists() {
        let service = WatchSyncService.shared
        #expect(service != nil)
    }

    @Test @MainActor func initialStateIsDefault() {
        let service = WatchSyncService.shared
        #expect(service.lastReceivedBookTitle == nil)
        #expect(service.lastReceivedPosition == 0)
    }
}
```

**Step 2:** Create the file, build, test, commit

---

## Task W3: Integrate WatchSyncService into iPhone App

Wire up the sync service on the iPhone side so books are sent to Watch.

**Files:**
- Modify: `SpeedRead/SpeedReadApp.swift` — add WatchSyncService activation
- Modify: `SpeedRead/Views/LibraryView.swift` — add "Send to Watch" button per book
- Modify: `SpeedRead/Views/RSVPView.swift` — sync reading position on pause/dismiss

**SpeedReadApp.swift changes:**
```swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .onAppear { syncService.activate() }
        }
        .modelContainer(for: Book.self)
    }
}
```

**LibraryView.swift — add context menu to BookRowView:**
Add a "Send to Watch" context menu option that calls `syncService.sendBook()`.

**RSVPView.swift — sync position on dismiss:**
Add position sync via `syncService.syncReadingPosition()` in onDisappear.

---

## Task W4: Watch App Views

Create the three Watch screens.

**Files:**
- Create: `SpeedReadWatch/Views/NowReadingView.swift`
- Create: `SpeedReadWatch/Views/WatchRSVPView.swift`
- Create: `SpeedReadWatch/Views/WatchSettingsView.swift`
- Modify: `SpeedReadWatch/ContentView.swift`

### NowReadingView (landing screen)
```swift
struct NowReadingView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @State private var showRSVP = false

    var body: some View {
        if let title = syncService.lastReceivedBookTitle,
           let text = syncService.lastReceivedBookText {
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button {
                    showRSVP = true
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showRSVP) {
                WatchRSVPView(
                    bookTitle: title,
                    words: text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty },
                    startingIndex: syncService.lastReceivedPosition
                )
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone.and.arrow.right.inward")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open SpeedRead on iPhone to add books")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### WatchRSVPView (playback + pause)
```swift
struct WatchRSVPView: View {
    let bookTitle: String
    let words: [String]
    let startingIndex: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var syncService: WatchSyncService
    @State private var engine = RSVPEngine()
    @State private var showSettings = false
    @State private var crownValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine.state == .playing {
                // Playing state — tap to pause
                RSVPWordView(segments: engine.currentSegments, fontSize: 22)
                    .onTapGesture { engine.pause() }
            } else {
                // Paused state
                VStack {
                    HStack {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 32, height: 32)

                        Spacer()

                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 4)

                    Spacer()

                    // Show current word context
                    RSVPWordView(segments: engine.currentSegments, fontSize: 20)

                    Spacer()

                    Button { engine.play() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Text("\(engine.wpm) WPM")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: max(1, Double(words.count - 1)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            engine.seek(to: Int(newValue))
        }
        .onAppear {
            engine.load(words: words, startingAt: startingIndex)
            crownValue = Double(startingIndex)
        }
        .onDisappear {
            syncService.syncReadingPosition(
                bookTitle: bookTitle,
                wordIndex: engine.currentIndex
            )
            engine.stop()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(engine: engine)
        }
    }
}
```

### WatchSettingsView (WPM via Digital Crown)
```swift
struct WatchSettingsView: View {
    @Bindable var engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @State private var wpmValue: Double = 300

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int(wpmValue))")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            Text("Words Per Minute")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Done") {
                engine.wpm = Int(wpmValue)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .focusable()
        .digitalCrownRotation(
            $wpmValue,
            from: 100,
            through: 1000,
            by: 25,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            wpmValue = Double(engine.wpm)
        }
    }
}
```

---

## Task W5: Share Code Between Targets

Ensure the Watch target has access to shared code:
- `Book.swift` (model)
- `ORPCalculator.swift`
- `WordTimer.swift`
- `RSVPEngine.swift`
- `RSVPWordView.swift`
- `WatchSyncService.swift`

Either add these files to both targets via target membership, or use conditional compilation where needed.

---

## Task W6: Final Build + Test + Verification

1. Build both iOS and watchOS schemes
2. Run all tests
3. Verify Watch simulator launches and shows "Open SpeedRead on iPhone"
4. Commit final state

---

## Dependency Graph

```
W1 (Add Target) → W2 (WatchSyncService) → W3 (iPhone Integration)
                                          → W4 (Watch Views)
                                          → W5 (Share Code)
                                          → W6 (Final Verification)
```
