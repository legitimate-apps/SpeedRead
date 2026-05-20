# Watch Sync Feedback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add rich feedback to iPhone-to-Watch book sync and persist books on Watch so they survive app restarts.

**Architecture:** Add send state tracking and toast UI on iPhone side, receiving state and persistence on Watch side. WatchSyncService gets new published properties for transfer status. LibraryView gets a toast overlay. NowReadingView gets a receiving card. Watch persists book data as JSON.

**Tech Stack:** SwiftUI, WatchConnectivity, Foundation (JSONEncoder/Decoder, FileManager)

---

### Task 1: Add Transfer State Tracking to WatchSyncService (iPhone side)

**Files:**
- Modify: `SpeedRead/Connectivity/WatchSyncService.swift`

**Step 1: Add transfer state enum and published properties**

Add after line 11 (`@Published var lastReceivedPosition`), inside the `#if os(iOS)` or as cross-platform with conditional usage:

```swift
#if os(iOS)
enum SendState: Equatable {
    case idle
    case sending(String) // book title
    case sent(String)
    case failed(String) // error message
}

@Published var sendState: SendState = .idle
#endif
```

**Step 2: Replace sendBook with error handling and state tracking**

Replace the existing `sendBook` method (lines 24-31):

```swift
#if os(iOS)
func sendBook(title: String, author: String, text: String) {
    guard WCSession.default.activationState == .activated else {
        sendState = .failed("Watch not connected")
        clearSendStateAfterDelay()
        return
    }
    guard WCSession.default.isReachable else {
        sendState = .failed("Watch not reachable")
        clearSendStateAfterDelay()
        return
    }

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).txt")
    do {
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        WCSession.default.transferFile(tempURL, metadata: ["title": title, "author": author])
        sendState = .sending(title)
    } catch {
        sendState = .failed("Failed to prepare book")
        clearSendStateAfterDelay()
    }
}

private func clearSendStateAfterDelay() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        self.sendState = .idle
    }
}
#endif
```

**Step 3: Add transfer completion delegate method**

Add after the `sessionDidDeactivate` method (line 52), still inside `#if os(iOS)`:

```swift
func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    DispatchQueue.main.async {
        if let error = error {
            self.sendState = .failed(error.localizedDescription)
        } else {
            let title = fileTransfer.file.metadata?["title"] as? String ?? "Book"
            self.sendState = .sent(title)
        }
        self.clearSendStateAfterDelay()
    }
}
```

**Step 4: Build**

Run: `cd "<PROJECT_DIR>" && xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add SpeedRead/Connectivity/WatchSyncService.swift
git commit -m "feat: add transfer state tracking to WatchSyncService for send feedback"
```

---

### Task 2: Add Toast Overlay to LibraryView (iPhone side)

**Files:**
- Modify: `SpeedRead/Views/LibraryView.swift`

**Step 1: Add toast overlay to the NavigationStack**

Add a `.overlay` modifier after the `.alert` modifier (after line 48), before the closing `}` of the NavigationStack:

```swift
.overlay(alignment: .bottom) {
    if case .sending(let title) = syncService.sendState {
        SendToast(icon: "arrow.up.circle", message: "Sending \(title)...", color: .blue)
    } else if case .sent(let title) = syncService.sendState {
        SendToast(icon: "checkmark.circle.fill", message: "Sent \(title) to Watch", color: .green)
    } else if case .failed(let error) = syncService.sendState {
        SendToast(icon: "exclamationmark.triangle.fill", message: error, color: .red)
    }
}
.animation(.easeInOut, value: syncService.sendState != .idle)
```

**Step 2: Add SendToast view at the bottom of the file**

Add after the `BookRowView` struct (after line 125):

```swift
private struct SendToast: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

**Step 3: Build**

Run: `cd "<PROJECT_DIR>" && xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SpeedRead/Views/LibraryView.swift
git commit -m "feat: add send-to-watch toast feedback in LibraryView"
```

---

### Task 3: Add Watch-Side Persistence to WatchSyncService

**Files:**
- Modify: `SpeedRead/Connectivity/WatchSyncService.swift`

**Step 1: Add persistence methods**

Add these methods inside the class, before the `// MARK: - WCSessionDelegate` comment (before line 44):

```swift
#if os(watchOS)
private struct PersistedBook: Codable {
    let title: String
    let author: String
    let text: String
    var position: Int
}

private static var persistURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("watchbook.json")
}

func loadPersistedBook() {
    guard let data = try? Data(contentsOf: Self.persistURL),
          let book = try? JSONDecoder().decode(PersistedBook.self, from: data) else { return }
    lastReceivedBookTitle = book.title
    lastReceivedBookAuthor = book.author
    lastReceivedBookText = book.text
    lastReceivedPosition = book.position
}

private func persistBook() {
    guard let title = lastReceivedBookTitle,
          let author = lastReceivedBookAuthor,
          let text = lastReceivedBookText else { return }
    let book = PersistedBook(title: title, author: author, text: text, position: lastReceivedPosition)
    try? JSONEncoder().encode(book).write(to: Self.persistURL)
}
#endif
```

**Step 2: Call persistBook after receiving a file**

Update the `session(_:didReceive file:)` method (line 66-75) to call persist after setting properties:

```swift
func session(_ session: WCSession, didReceive file: WCSessionFile) {
    let metadata = file.metadata ?? [:]
    if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
        DispatchQueue.main.async {
            self.lastReceivedBookTitle = metadata["title"] as? String
            self.lastReceivedBookAuthor = metadata["author"] as? String
            self.lastReceivedBookText = text
            self.lastReceivedPosition = 0
            #if os(watchOS)
            self.persistBook()
            #endif
        }
    }
}
```

**Step 3: Also persist when reading position changes**

Update the `session(_:didReceiveApplicationContext:)` method (line 55-63) to persist:

```swift
func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async {
        if let title = applicationContext["bookTitle"] as? String {
            self.lastReceivedBookTitle = title
        }
        if let index = applicationContext["wordIndex"] as? Int {
            self.lastReceivedPosition = index
        }
        #if os(watchOS)
        self.persistBook()
        #endif
    }
}
```

**Step 4: Call loadPersistedBook in activate()**

Update the `activate()` method (lines 17-21) to load persisted data:

```swift
func activate() {
    guard WCSession.isSupported() else { return }
    #if os(watchOS)
    loadPersistedBook()
    #endif
    WCSession.default.delegate = self
    WCSession.default.activate()
}
```

**Step 5: Build for Watch**

Run: `cd "<PROJECT_DIR>" && xcodebuild build -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (44mm)' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add SpeedRead/Connectivity/WatchSyncService.swift
git commit -m "feat: persist received book to JSON on Watch for app restart survival"
```

---

### Task 4: Add Receiving Feedback to NowReadingView (Watch side)

**Files:**
- Modify: `SpeedRead/Connectivity/WatchSyncService.swift` (add receiving state)
- Modify: `SpeedReadWatch Watch App/Views/NowReadingView.swift` (add receiving card)

**Step 1: Add receiving state to WatchSyncService**

Add after the `lastReceivedPosition` property (line 11):

```swift
#if os(watchOS)
@Published var isReceiving = false
@Published var receivingTitle: String?
#endif
```

**Step 2: Update the didReceive file delegate to track receiving state**

The `session(_:didReceive file:)` needs to signal receiving. However, WatchConnectivity doesn't have a "will receive" callback. We can use the `didReceive` to briefly show a receiving state before transitioning. Update to:

```swift
func session(_ session: WCSession, didReceive file: WCSessionFile) {
    let metadata = file.metadata ?? [:]
    #if os(watchOS)
    DispatchQueue.main.async {
        self.isReceiving = true
        self.receivingTitle = metadata["title"] as? String
    }
    #endif
    if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
        DispatchQueue.main.async {
            self.lastReceivedBookTitle = metadata["title"] as? String
            self.lastReceivedBookAuthor = metadata["author"] as? String
            self.lastReceivedBookText = text
            self.lastReceivedPosition = 0
            #if os(watchOS)
            self.persistBook()
            WKInterfaceDevice.current().play(.success)
            self.isReceiving = false
            self.receivingTitle = nil
            #endif
        }
    }
}
```

Note: Add `import WatchKit` at the top of the file, guarded:

```swift
#if os(watchOS)
import WatchKit
#endif
```

**Step 3: Update NowReadingView to show receiving state**

Replace the entire body of NowReadingView:

```swift
var body: some View {
    Group {
        if syncService.isReceiving, let title = syncService.receivingTitle {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.red)
                Text("Receiving")
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .transition(.opacity)
        } else if let title = syncService.lastReceivedBookTitle,
                  syncService.lastReceivedBookText != nil {
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

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
                WatchRSVPView()
                    .environmentObject(syncService)
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone.and.arrow.right.inward")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open SpeedRead on iPhone to add books!")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    .animation(.easeInOut, value: syncService.isReceiving)
}
```

**Step 4: Build for both platforms**

Run: `cd "<PROJECT_DIR>" && xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -3 && xcodebuild build -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (44mm)' -quiet 2>&1 | tail -3`
Expected: Both BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add SpeedRead/Connectivity/WatchSyncService.swift "SpeedReadWatch Watch App/Views/NowReadingView.swift"
git commit -m "feat: add receiving feedback card and haptic on Watch when book arrives"
```

---

### Task 5: Run Full Test Suite

**Step 1: Run all tests**

Run: `cd "<PROJECT_DIR>" && xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10`
Expected: All tests pass, no regressions

**Step 2: Verify Watch build**

Run: `cd "<PROJECT_DIR>" && xcodebuild build -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (44mm)' -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED
