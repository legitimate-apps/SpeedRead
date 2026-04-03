# Apple Watch Library & Style Upgrade — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the Apple Watch app from single-book mode to a multi-book library with browsing, detail views, and bookshelf-quality styling per the approved design.

**Architecture:** TabView(.verticalPage) with Now Reading + Library tabs. NavigationStack in Library pushes to book detail. Multi-book JSON persistence with UUID deduplication. WatchSyncService refactored from scattered published properties to a single @Published WatchLibrary.

**Tech Stack:** SwiftUI (watchOS 10.6+), WatchConnectivity, Codable JSON persistence

**Design doc:** `docs/plans/2026-04-03-watch-library-design.md`

---

### Task 1: Add WatchBook and WatchLibrary Models

**Files:**
- Create: `SpeedReadWatch Watch App/Shared/WatchBook.swift`

**Step 1: Create the models**

```swift
//  WatchBook.swift
import Foundation

struct WatchBook: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let text: String
    var lastReadIndex: Int
    var lastReadDate: Date?
    let wordCount: Int
    let dateAdded: Date

    var words: [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var progress: Double {
        guard wordCount > 0 else { return 0 }
        return Double(lastReadIndex) / Double(wordCount)
    }
}

struct WatchLibrary: Codable {
    var books: [WatchBook]
    var currentBookId: UUID?

    static let empty = WatchLibrary(books: [], currentBookId: nil)

    var currentBook: WatchBook? {
        guard let id = currentBookId else { return nil }
        return books.first { $0.id == id }
    }

    var sortedBooks: [WatchBook] {
        books.sorted { $0.dateAdded > $1.dateAdded }
    }

    mutating func addBook(_ book: WatchBook) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.append(book)
        currentBookId = book.id
    }

    mutating func removeBook(id: UUID) {
        books.removeAll { $0.id == id }
        if currentBookId == id {
            currentBookId = books.first?.id
        }
    }

    mutating func updatePosition(bookId: UUID, index: Int) {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[i].lastReadIndex = index
        books[i].lastReadDate = Date()
    }

    mutating func setCurrentBook(id: UUID) {
        guard books.contains(where: { $0.id == id }) else { return }
        currentBookId = id
    }
}
```

**Step 2: Add file to Watch target in Xcode**

This file lives in `SpeedReadWatch Watch App/Shared/` alongside the other shared files (RSVPEngine, Theme, etc.). It must be added to the Watch App target in Xcode's project navigator.

**Step 3: Verify it builds**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add "SpeedReadWatch Watch App/Shared/WatchBook.swift"
git commit -m "feat(watch): add WatchBook and WatchLibrary data models"
```

---

### Task 2: Add SpineColor to Watch Target

**Files:**
- Create: `SpeedReadWatch Watch App/Shared/SpineColor.swift`

The Watch app needs `SpineColor` for the accent bars on library rows and detail view backgrounds. Copy the existing implementation from the iOS target.

**Step 1: Create the file**

```swift
//  SpineColor.swift
import SwiftUI

enum SpineColor {
    static let classicPalette: [Color] = [
        Color(red: 0x00/255.0, green: 0x5F/255.0, blue: 0x73/255.0),
        Color(red: 0x7B/255.0, green: 0x2D/255.0, blue: 0x26/255.0),
        Color(red: 0x2D/255.0, green: 0x4A/255.0, blue: 0x22/255.0),
        Color(red: 0x1B/255.0, green: 0x2A/255.0, blue: 0x4A/255.0),
        Color(red: 0x8B/255.0, green: 0x4A/255.0, blue: 0x2B/255.0),
        Color(red: 0x5B/255.0, green: 0x2C/255.0, blue: 0x5E/255.0),
        Color(red: 0x4A/255.0, green: 0x5A/255.0, blue: 0x6A/255.0),
        Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x2A/255.0),
        Color(red: 0x3E/255.0, green: 0x27/255.0, blue: 0x23/255.0),
        Color(red: 0x6B/255.0, green: 0x3A/255.0, blue: 0x2A/255.0),
    ]

    static func color(for title: String) -> Color {
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return classicPalette[abs(hash) % classicPalette.count]
    }
}
```

**Step 2: Add to Watch target in Xcode, verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Shared/SpineColor.swift"
git commit -m "feat(watch): add SpineColor for library accent colors"
```

---

### Task 3: Refactor WatchSyncService for Multi-Book Library

**Files:**
- Modify: `SpeedReadWatch Watch App/Shared/WatchSyncService.swift` (entire file)
- Modify: `SpeedRead/Views/LibraryView.swift:131-132` (sendBook call)

This is the largest task. The WatchSyncService changes from single-book published properties to a `@Published var library: WatchLibrary` with computed `currentBook`.

**Step 1: Update iPhone-side `sendBook` to include UUID**

In `SpeedRead/Views/LibraryView.swift`, change the sendBook call at line 132:

```swift
// Before:
syncService.sendBook(title: book.title, author: book.author, text: book.extractedText)

// After:
syncService.sendBook(id: book.id, title: book.title, author: book.author, text: book.extractedText, wordCount: book.wordCount)
```

**Step 2: Update `sendBook` signature and message in WatchSyncService**

Replace the `sendBook` function (iOS side) — now accepts `id`, `wordCount`:

```swift
#if os(iOS)
func sendBook(id: UUID, title: String, author: String, text: String, wordCount: Int) {
    guard WCSession.default.activationState == .activated else {
        sendState = .failed("Watch not connected")
        clearSendStateAfterDelay()
        return
    }

    sendState = .sending(title)
    let message: [String: Any] = [
        "id": id.uuidString,
        "title": title,
        "author": author,
        "text": text,
        "wordCount": wordCount
    ]

    print("[WatchSync] Sending '\(title)' — isReachable=\(WCSession.default.isReachable) isPaired=\(WCSession.default.isPaired)")

    if WCSession.default.isReachable {
        WCSession.default.sendMessage(message, replyHandler: { reply in
            print("[WatchSync] sendMessage reply: \(reply)")
            DispatchQueue.main.async {
                self.sendState = .sent(title)
                self.clearSendStateAfterDelay()
            }
        }, errorHandler: { error in
            print("[WatchSync] sendMessage FAILED: \(error.localizedDescription) — falling back to transferFile")
            self.fallbackToFileTransfer(id: id, title: title, author: author, text: text, wordCount: wordCount)
        })
    } else {
        fallbackToFileTransfer(id: id, title: title, author: author, text: text, wordCount: wordCount)
    }
}

private func fallbackToFileTransfer(id: UUID, title: String, author: String, text: String, wordCount: Int) {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).txt")
    do {
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        WCSession.default.transferFile(tempURL, metadata: [
            "id": id.uuidString,
            "title": title,
            "author": author,
            "wordCount": wordCount
        ])
    } catch {
        DispatchQueue.main.async {
            self.sendState = .failed("Failed to prepare book")
            self.clearSendStateAfterDelay()
        }
    }
}
#endif
```

**Step 3: Replace Watch-side published properties and persistence**

Remove the old properties and `PersistedBook`. Replace with:

```swift
// Published state (replaces old scattered properties)
@Published var library: WatchLibrary = .empty

#if os(watchOS)
@Published var isReceiving = false
@Published var receivingTitle: String?
#endif

var currentBook: WatchBook? { library.currentBook }
```

Replace persistence:

```swift
#if os(watchOS)
private static var libraryURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("watchlibrary.json")
}

private static var legacyBookURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("watchbook.json")
}

func loadLibrary() {
    // Try new format first
    if let data = try? Data(contentsOf: Self.libraryURL),
       let lib = try? JSONDecoder().decode(WatchLibrary.self, from: data) {
        library = lib
        return
    }
    // Migrate from legacy single-book format
    if let data = try? Data(contentsOf: Self.legacyBookURL),
       let legacy = try? JSONDecoder().decode(LegacyPersistedBook.self, from: data) {
        let book = WatchBook(
            id: UUID(),
            title: legacy.title,
            author: legacy.author,
            text: legacy.text,
            lastReadIndex: legacy.position,
            lastReadDate: nil,
            wordCount: legacy.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count,
            dateAdded: Date()
        )
        library = WatchLibrary(books: [book], currentBookId: book.id)
        persistLibrary()
        try? FileManager.default.removeItem(at: Self.legacyBookURL)
    }
}

private struct LegacyPersistedBook: Codable {
    let title: String
    let author: String
    let text: String
    var position: Int
}

func persistLibrary() {
    try? JSONEncoder().encode(library).write(to: Self.libraryURL)
}
#endif
```

**Step 4: Update `activate()` to call `loadLibrary()`**

```swift
func activate() {
    #if os(watchOS)
    loadLibrary()
    #endif
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
}
```

**Step 5: Update receive handlers for multi-book**

```swift
func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    guard let title = message["title"] as? String,
          let author = message["author"] as? String,
          let text = message["text"] as? String else {
        replyHandler(["status": "error"])
        return
    }

    let bookId: UUID
    if let idString = message["id"] as? String, let parsed = UUID(uuidString: idString) {
        bookId = parsed
    } else {
        bookId = UUID()
    }
    let wordCount = message["wordCount"] as? Int ??
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

    DispatchQueue.main.async {
        #if os(watchOS)
        self.isReceiving = true
        self.receivingTitle = title

        if self.library.books.contains(where: { $0.id == bookId }) {
            WKInterfaceDevice.current().play(.click)
        } else {
            let book = WatchBook(
                id: bookId, title: title, author: author, text: text,
                lastReadIndex: 0, lastReadDate: nil, wordCount: wordCount, dateAdded: Date()
            )
            self.library.addBook(book)
            self.persistLibrary()
            WKInterfaceDevice.current().play(.success)
        }

        self.isReceiving = false
        self.receivingTitle = nil
        #endif
    }
    replyHandler(["status": "ok"])
}

func session(_ session: WCSession, didReceive file: WCSessionFile) {
    let metadata = file.metadata ?? [:]
    #if os(watchOS)
    DispatchQueue.main.async { self.isReceiving = true; self.receivingTitle = metadata["title"] as? String }
    #endif

    guard let text = try? String(contentsOf: file.fileURL, encoding: .utf8),
          let title = metadata["title"] as? String,
          let author = metadata["author"] as? String else { return }

    let bookId: UUID
    if let idString = metadata["id"] as? String, let parsed = UUID(uuidString: idString) {
        bookId = parsed
    } else {
        bookId = UUID()
    }
    let wordCount = metadata["wordCount"] as? Int ??
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

    DispatchQueue.main.async {
        #if os(watchOS)
        if self.library.books.contains(where: { $0.id == bookId }) {
            WKInterfaceDevice.current().play(.click)
        } else {
            let book = WatchBook(
                id: bookId, title: title, author: author, text: text,
                lastReadIndex: 0, lastReadDate: nil, wordCount: wordCount, dateAdded: Date()
            )
            self.library.addBook(book)
            self.persistLibrary()
            WKInterfaceDevice.current().play(.success)
        }
        self.isReceiving = false
        self.receivingTitle = nil
        #endif
    }
}
```

**Step 6: Update position sync to include bookId**

```swift
func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int) {
    #if os(watchOS)
    library.updatePosition(bookId: bookId, index: wordIndex)
    persistLibrary()
    #endif
    guard WCSession.default.activationState == .activated else { return }
    try? WCSession.default.updateApplicationContext([
        "bookId": bookId.uuidString,
        "bookTitle": bookTitle,
        "wordIndex": wordIndex,
        "timestamp": Date().timeIntervalSince1970
    ])
}

func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async {
        if let idString = applicationContext["bookId"] as? String,
           let bookId = UUID(uuidString: idString),
           let index = applicationContext["wordIndex"] as? Int {
            self.library.updatePosition(bookId: bookId, index: index)
            #if os(watchOS)
            self.persistLibrary()
            #endif
        }
    }
}
```

**Step 7: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Also build iOS:
Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedRead" -destination "platform=iOS Simulator,name=iPhone 16" -quiet 2>&1 | tail -5`

Expected: Both BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add "SpeedReadWatch Watch App/Shared/WatchSyncService.swift" "SpeedRead/Views/LibraryView.swift" "SpeedRead/Connectivity/WatchSyncService.swift"
git commit -m "feat(watch): refactor WatchSyncService for multi-book library with UUID dedup"
```

---

### Task 4: Create WatchLibraryView (List)

**Files:**
- Create: `SpeedReadWatch Watch App/Views/WatchLibraryView.swift`

**Step 1: Create the library list view**

```swift
//  WatchLibraryView.swift
import SwiftUI

struct WatchLibraryView: View {
    @EnvironmentObject var syncService: WatchSyncService

    var body: some View {
        NavigationStack {
            Group {
                if syncService.library.books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("Library")
            .containerBackground(Color.inkBlack.gradient, for: .navigation)
            .navigationDestination(for: WatchBook.self) { book in
                WatchBookDetailView(book: book)
            }
        }
    }

    private var bookList: some View {
        List {
            ForEach(syncService.library.sortedBooks) { book in
                NavigationLink(value: book) {
                    bookRow(book)
                }
                .listRowBackground(Color.walnut.opacity(0.3))
            }
            .onDelete(perform: deleteBooks)
        }
    }

    private func bookRow(_ book: WatchBook) -> some View {
        HStack(spacing: 10) {
            // Spine accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(SpineColor.color(for: book.title))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.parchment)
                    .lineLimit(2)

                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(Color.parchment.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Progress ring or "now reading" indicator
            if book.id == syncService.library.currentBookId {
                Circle()
                    .fill(Color.crimsonSoft)
                    .frame(width: 8, height: 8)
            } else if book.progress > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.parchment.opacity(0.15), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: book.progress)
                        .stroke(Color.agedGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(Color.agedGold)
            Text("Send books from your iPhone library")
                .font(.displayFont(size: 13, weight: .regular))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.parchment.opacity(0.6))
        }
        .padding()
    }

    private func deleteBooks(at offsets: IndexSet) {
        let sorted = syncService.library.sortedBooks
        for index in offsets {
            syncService.library.removeBook(id: sorted[index].id)
        }
        syncService.persistLibrary()
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/WatchLibraryView.swift"
git commit -m "feat(watch): add WatchLibraryView with spine-colored list rows"
```

---

### Task 5: Create WatchBookDetailView

**Files:**
- Create: `SpeedReadWatch Watch App/Views/WatchBookDetailView.swift`

**Step 1: Create the detail view**

```swift
//  WatchBookDetailView.swift
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchBookDetailView: View {
    let book: WatchBook
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private var spineColor: Color {
        SpineColor.color(for: book.title)
    }

    private var latestBook: WatchBook {
        syncService.library.books.first { $0.id == book.id } ?? book
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title & Author
                Text(latestBook.title)
                    .font(.displayFont(size: 18, weight: .semibold))
                    .foregroundStyle(Color.parchment)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(latestBook.author)
                    .font(.displayFont(size: 13, weight: .regular))
                    .foregroundStyle(Color.parchment.opacity(0.7))
                    .multilineTextAlignment(.center)

                // Divider
                Rectangle()
                    .fill(Color.agedGold.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal)

                // Stats
                HStack {
                    VStack(spacing: 2) {
                        Text("\(Int(latestBook.progress * 100))%")
                            .font(.numeric(size: 18))
                            .foregroundStyle(Color.agedGold)
                        Text("Progress")
                            .font(.caption)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Text(latestBook.wordCount.formatted())
                            .font(.numeric(size: 18))
                            .foregroundStyle(Color.parchment)
                        Text("Words")
                            .font(.caption)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.parchment.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.agedGold)
                            .frame(width: geo.size.width * latestBook.progress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal)

                // Read button
                Button {
                    syncService.library.setCurrentBook(id: book.id)
                    syncService.persistLibrary()
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                } label: {
                    Text(latestBook.lastReadIndex > 0 ? "Continue Reading" : "Read")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crimsonSoft)

                // Delete button
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Remove from Watch")
                        .font(.caption)
                        .foregroundStyle(Color.crimsonSoft.opacity(0.7))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Remove this book?", isPresented: $showDeleteConfirmation) {
                    Button("Remove", role: .destructive) {
                        syncService.library.removeBook(id: book.id)
                        syncService.persistLibrary()
                        dismiss()
                    }
                }
            }
            .padding(.top, 8)
        }
        .containerBackground(spineColor.gradient, for: .navigation)
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/WatchBookDetailView.swift"
git commit -m "feat(watch): add WatchBookDetailView with spine-color gradient background"
```

---

### Task 6: Update NowReadingView for Library

**Files:**
- Modify: `SpeedReadWatch Watch App/Views/NowReadingView.swift`

**Step 1: Rewrite NowReadingView to read from library**

Replace the entire file:

```swift
import SwiftUI

struct NowReadingView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @State private var showRSVP = false

    private var currentBook: WatchBook? { syncService.currentBook }

    var body: some View {
        ZStack {
            Color.walnut.ignoresSafeArea()

            Group {
                if syncService.isReceiving, let title = syncService.receivingTitle {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.agedGold)
                        Text("Receiving")
                            .font(.displayFont(size: 16, weight: .semibold))
                            .foregroundStyle(Color.parchment)
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.parchment.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding()
                    .transition(.opacity)
                } else if let book = currentBook {
                    VStack(spacing: 12) {
                        Text(book.title)
                            .font(.displayFont(size: 15, weight: .semibold))
                            .foregroundStyle(Color.parchment)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Button {
                            showRSVP = true
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.crimsonSoft)
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
                        Image(systemName: "books.vertical")
                            .font(.title2)
                            .foregroundStyle(Color.agedGold)
                        Text("Swipe up to browse your library")
                            .font(.displayFont(size: 13, weight: .regular))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .padding()
                }
            }
        }
        .animation(.easeInOut, value: syncService.isReceiving)
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/NowReadingView.swift"
git commit -m "feat(watch): update NowReadingView to read from library"
```

---

### Task 7: Update WatchRSVPView for Library

**Files:**
- Modify: `SpeedReadWatch Watch App/Views/WatchRSVPView.swift`

**Step 1: Update WatchRSVPView to use currentBook**

Replace references to the old scattered properties:

```swift
import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false
    @State private var crownValue: Double = 0

    private var currentBook: WatchBook? { syncService.currentBook }

    private var words: [String] {
        currentBook?.words ?? []
    }

    var body: some View {
        ZStack {
            Color.rsvpBackground.ignoresSafeArea()

            if engine.state == .playing {
                RSVPWordView(segments: engine.currentSegments, fontSize: 20)
                    .onTapGesture { engine.pause() }
                    .onLongPressGesture {
                        engine.pause()
                        showSettings = true
                    }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            if let book = currentBook {
                                syncService.syncReadingPosition(
                                    bookId: book.id,
                                    bookTitle: book.title,
                                    wordIndex: engine.currentIndex
                                )
                            }
                            engine.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.walnut.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.walnut.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    Spacer()

                    RSVPWordView(segments: engine.currentSegments, fontSize: 18)

                    Spacer()

                    Button { engine.play() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.crimsonSoft)
                    }
                    .buttonStyle(.plain)

                    Text("\(engine.wpm) WPM")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.agedGold)
                        .padding(.bottom, 4)
                }
                .onLongPressGesture {
                    showSettings = true
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
            if engine.state != .playing {
                engine.seek(to: Int(newValue))
            }
        }
        .onAppear {
            guard let book = currentBook else { return }
            engine.load(words: book.words, startingAt: book.lastReadIndex)
            crownValue = Double(book.lastReadIndex)
        }
        .onDisappear {
            if let book = currentBook {
                syncService.syncReadingPosition(
                    bookId: book.id,
                    bookTitle: book.title,
                    wordIndex: engine.currentIndex
                )
            }
            engine.stop()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(engine: engine)
        }
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/WatchRSVPView.swift"
git commit -m "feat(watch): update WatchRSVPView to use library currentBook"
```

---

### Task 8: Wire Up TabView in SpeedReadWatchApp

**Files:**
- Modify: `SpeedReadWatch Watch App/SpeedReadWatchApp.swift`

**Step 1: Replace root view with TabView**

```swift
import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                NowReadingView()
                    .containerBackground(Color.walnut.gradient, for: .tabView)

                WatchLibraryView()
                    .containerBackground(Color.inkBlack.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(syncService)
            .onAppear { syncService.activate() }
        }
    }
}
```

**Step 2: Verify build**

Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/SpeedReadWatchApp.swift"
git commit -m "feat(watch): wire up TabView with NowReading + Library tabs"
```

---

### Task 9: Clean Up and Delete Unused ContentView

**Files:**
- Delete: `SpeedReadWatch Watch App/ContentView.swift`

**Step 1: Remove the unused placeholder**

```bash
rm "SpeedReadWatch Watch App/ContentView.swift"
```

**Step 2: Remove from Xcode project** (if it causes build issues — may auto-resolve)

Verify build:
Run: `xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (file was unused, removal should be clean)

**Step 3: Commit**

```bash
git add -u
git commit -m "chore(watch): remove unused ContentView placeholder"
```

---

### Task 10: Final Integration Verification

**Step 1: Build both targets**

```bash
xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedRead" -destination "platform=iOS Simulator,name=iPhone 16" -quiet 2>&1 | tail -5
xcodebuild build -project "SpeedRead.xcodeproj" -scheme "SpeedReadWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch SE (44mm)" -quiet 2>&1 | tail -5
```

Expected: Both BUILD SUCCEEDED

**Step 2: Run existing tests**

```bash
xcodebuild test -project "SpeedRead.xcodeproj" -scheme "SpeedRead" -destination "platform=iOS Simulator,name=iPhone 16" -quiet 2>&1 | tail -20
```

Expected: All 63 tests pass

**Step 3: Manual verification checklist**

On watchOS Simulator:
- [ ] App launches to TabView with NowReading tab
- [ ] Scroll down to see Library tab (empty state)
- [ ] Empty state shows "Send books from your iPhone library"

On iOS Simulator + Watch:
- [ ] "Send to Watch" from LibraryView context menu works
- [ ] Book appears in Watch library list with spine color accent
- [ ] Sending same book again does not create duplicate
- [ ] Tap book row → navigates to detail view with spine-color gradient
- [ ] Detail shows title, author, progress, word count
- [ ] "Read" button sets as current and dismisses to NowReading
- [ ] RSVP launches and reads from correct book
- [ ] Close RSVP → position saved and synced
- [ ] Swipe to delete works in library list
- [ ] "Remove from Watch" in detail view works with confirmation

**Step 4: Commit final state if any fixes were needed**

```bash
git add -A
git commit -m "feat(watch): complete multi-book library with styled UI"
```
