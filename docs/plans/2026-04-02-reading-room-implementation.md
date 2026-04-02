# The Reading Room — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign SpeedRead's visual layer into a warm "cozy library" experience without changing engine, extraction, sync, or data logic.

**Architecture:** Pure view-layer changes. New shared `Theme.swift` provides colors/typography. Existing views are rewritten in place. New `OnboardingView` and `BookSpineView`/`BookshelfRowView` components added. No model or engine changes.

**Tech Stack:** SwiftUI, SF Serif (New York), SF Mono, SwiftData (unchanged), WatchConnectivity (unchanged)

---

### Task 1: Create Theme — Color System

**Files:**
- Create: `SpeedRead/Theme/Theme.swift`

**Step 1: Create the color extension file**

```swift
//  Theme.swift
import SwiftUI

extension Color {
    // MARK: - Core Palette
    static let walnut = Color(red: 0x3E/255, green: 0x27/255, blue: 0x23/255)
    static let walnutLight = Color(red: 0x5D/255, green: 0x40/255, blue: 0x37/255)
    static let parchment = Color(red: 0xFF/255, green: 0xF8/255, blue: 0xE7/255)
    static let parchmentDark = Color(red: 0xF0/255, green: 0xE6/255, blue: 0xD0/255)
    static let inkBlack = Color(red: 0x1C/255, green: 0x14/255, blue: 0x10/255)
    static let crimson = Color(red: 0xC6/255, green: 0x28/255, blue: 0x28/255)
    static let crimsonSoft = Color(red: 0xD4/255, green: 0x57/255, blue: 0x4A/255)
    static let agedGold = Color(red: 0xC8/255, green: 0xA9/255, blue: 0x51/255)
    static let lamplight = Color(red: 0xFF/255, green: 0xE0/255, blue: 0xA0/255)

    // MARK: - RSVP Mode
    static let rsvpBackground = Color(red: 0x1A/255, green: 0x12/255, blue: 0x10/255)
    static let rsvpText = Color(red: 0xF5/255, green: 0xED/255, blue: 0xE0/255)
}
```

**Step 2: Add the file to the Xcode project**

Ensure `Theme.swift` is added to both the SpeedRead (iOS) target AND SpeedReadWatch Watch App target so colors are shared.

**Step 3: Build to verify no conflicts**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SpeedRead/Theme/Theme.swift
git commit -m "feat: add Reading Room color system (Theme.swift)"
```

---

### Task 2: Create Theme — Typography Helpers

**Files:**
- Modify: `SpeedRead/Theme/Theme.swift`

**Step 1: Add font helpers to Theme.swift**

Append to the file:

```swift
// MARK: - Typography

extension Font {
    // Display — New York (SF Serif)
    static func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // Body — New York (SF Serif)
    static func bodySerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // RSVP — SF Mono
    static func rsvpWord(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    // Numeric displays — SF Mono
    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Theme/Theme.swift
git commit -m "feat: add typography helpers for serif, mono, and display fonts"
```

---

### Task 3: Create Book Spine Color Generator

**Files:**
- Create: `SpeedRead/Theme/SpineColor.swift`

**Step 1: Write the failing test**

Create `SpeedReadTests/SpineColorTests.swift`:

```swift
import Testing
@testable import SpeedRead

struct SpineColorTests {
    @Test func sameTitle_returnsSameIndex() {
        let index1 = SpineColor.colorIndex(for: "Alice in Wonderland")
        let index2 = SpineColor.colorIndex(for: "Alice in Wonderland")
        #expect(index1 == index2)
    }

    @Test func differentTitles_canReturnDifferentIndices() {
        // With 10 colors, different titles should eventually differ
        let titles = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon",
                      "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda"]
        let indices = Set(titles.map { SpineColor.colorIndex(for: $0) })
        #expect(indices.count > 1)
    }

    @Test func colorIndex_withinRange() {
        let index = SpineColor.colorIndex(for: "Test Book")
        #expect(index >= 0)
        #expect(index < SpineColor.spineColors.count)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing SpeedReadTests/SpineColorTests 2>&1 | tail -10`
Expected: FAIL — `SpineColor` not found

**Step 3: Write minimal implementation**

Create `SpeedRead/Theme/SpineColor.swift`:

```swift
//  SpineColor.swift
import SwiftUI

enum SpineColor {
    static let spineColors: [Color] = [
        Color(red: 0x00/255, green: 0x5F/255, blue: 0x73/255), // deep teal
        Color(red: 0x7B/255, green: 0x2D/255, blue: 0x26/255), // burgundy
        Color(red: 0x2D/255, green: 0x4A/255, blue: 0x22/255), // forest green
        Color(red: 0x1B/255, green: 0x2A/255, blue: 0x4A/255), // navy
        Color(red: 0x8B/255, green: 0x4A/255, blue: 0x2B/255), // burnt sienna
        Color(red: 0x5B/255, green: 0x2C/255, blue: 0x5E/255), // plum
        Color(red: 0x4A/255, green: 0x5A/255, blue: 0x6A/255), // slate blue
        Color(red: 0x8B/255, green: 0x73/255, blue: 0x2A/255), // ochre
        Color(red: 0x3E/255, green: 0x27/255, blue: 0x23/255), // walnut
        Color(red: 0x6B/255, green: 0x3A/255, blue: 0x2A/255), // leather brown
    ]

    static func colorIndex(for title: String) -> Int {
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(hash) % spineColors.count
    }

    static func color(for title: String) -> Color {
        spineColors[colorIndex(for: title)]
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing SpeedReadTests/SpineColorTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SpeedRead/Theme/SpineColor.swift SpeedReadTests/SpineColorTests.swift
git commit -m "feat: add deterministic book spine color generator with tests"
```

---

### Task 4: Create BookSpineView Component

**Files:**
- Create: `SpeedRead/Views/BookSpineView.swift`

**Step 1: Create the book spine component**

```swift
//  BookSpineView.swift
import SwiftUI

struct BookSpineView: View {
    let title: String
    let author: String
    let progress: Double
    let wordCount: Int

    // Spine height varies by word count: 120-180pt
    private var spineHeight: CGFloat {
        let base: CGFloat = 120
        let extra = min(CGFloat(wordCount) / 50_000.0, 1.0) * 60
        return base + extra
    }

    private var spineColor: Color {
        SpineColor.color(for: title)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Spine body
            RoundedRectangle(cornerRadius: 4)
                .fill(spineColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.15))
                        .frame(width: 2)
                        .padding(.vertical, 8),
                    alignment: .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)

            // Title text (rotated vertically)
            VStack(spacing: 4) {
                Text(title)
                    .font(.displayFont(size: 11, weight: .semibold))
                    .foregroundStyle(.parchment)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(author)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(.parchment.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)

            // Progress indicator — gold line at bottom
            if progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.agedGold)
                        .frame(width: geo.size.width, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(0.8)
                }
            }
        }
        .frame(width: 60, height: spineHeight)
    }
}

#Preview {
    HStack(spacing: 8) {
        BookSpineView(title: "Alice in Wonderland", author: "Lewis Carroll", progress: 0.4, wordCount: 27000)
        BookSpineView(title: "The Metamorphosis", author: "Franz Kafka", progress: 0, wordCount: 15000)
        BookSpineView(title: "A Christmas Carol", author: "Charles Dickens", progress: 0.8, wordCount: 30000)
    }
    .padding()
    .background(Color.walnut)
}
```

**Step 2: Build and verify preview renders**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/BookSpineView.swift
git commit -m "feat: add BookSpineView component with generated spine colors"
```

---

### Task 5: Create BookshelfRowView Component

**Files:**
- Create: `SpeedRead/Views/BookshelfRowView.swift`

**Step 1: Create the shelf row component**

```swift
//  BookshelfRowView.swift
import SwiftUI

struct BookshelfRowView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Books sitting on the shelf
            HStack(alignment: .bottom, spacing: 8) {
                content
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 0)

            // Shelf plank
            shelfPlank
        }
    }

    private var shelfPlank: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.walnutLight,
                            Color.walnut,
                            Color.walnut.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 12)

            // Subtle edge highlight
            Rectangle()
                .fill(Color.lamplight.opacity(0.15))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 12)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

#Preview {
    ScrollView {
        BookshelfRowView {
            BookSpineView(title: "Alice", author: "Carroll", progress: 0.5, wordCount: 27000)
            BookSpineView(title: "Kafka", author: "Kafka", progress: 0, wordCount: 15000)
        }
    }
    .background(Color.parchment)
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/BookshelfRowView.swift
git commit -m "feat: add BookshelfRowView with walnut shelf plank"
```

---

### Task 6: Redesign LibraryView — The Bookshelf

**Files:**
- Modify: `SpeedRead/Views/LibraryView.swift` (full rewrite)

**Step 1: Rewrite LibraryView with shelf metaphor**

Replace the entire content of `LibraryView.swift`:

```swift
//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var syncService: WatchSyncService
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showError = false
    @State private var selectedBook: Book?

    private let booksPerShelf = 4

    private var shelves: [[Book]] {
        stride(from: 0, to: books.count, by: booksPerShelf).map {
            Array(books[$0..<min($0 + booksPerShelf, books.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.parchment.ignoresSafeArea()

                if books.isEmpty {
                    emptyLibraryView
                } else {
                    bookshelfView
                }
            }
            .navigationTitle("Your Library")
            .toolbarBackground(Color.parchment, for: .navigationBar)
            .task {
                SampleBookLoader(modelContext: modelContext).loadSampleBooksIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.crimsonSoft)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .overlay(alignment: .bottom) {
                if case .sending(let title) = syncService.sendState {
                    SendToast(icon: "arrow.up.circle", message: "Sending \(title)...", color: .agedGold)
                } else if case .sent(let title) = syncService.sendState {
                    SendToast(icon: "checkmark.circle.fill", message: "Sent \(title) to Watch", color: .agedGold)
                } else if case .failed(let error) = syncService.sendState {
                    SendToast(icon: "exclamationmark.triangle.fill", message: error, color: .crimsonSoft)
                }
            }
            .animation(.easeInOut, value: syncService.sendState != .idle)
        }
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            // Empty shelf visual
            BookshelfRowView { }
            BookshelfRowView { }

            Text("Your shelves are waiting...")
                .font(.displayFont(size: 20, weight: .regular))
                .italic()
                .foregroundStyle(.walnutLight)
                .padding(.top, 20)

            Button {
                showImporter = true
            } label: {
                Label("Import a Book", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.parchment)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.crimsonSoft, in: Capsule())
            }
        }
        .padding()
    }

    private var bookshelfView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelfBooks in
                    BookshelfRowView {
                        ForEach(shelfBooks) { book in
                            NavigationLink(value: book) {
                                BookSpineView(
                                    title: book.title,
                                    author: book.author,
                                    progress: book.progress,
                                    wordCount: book.wordCount
                                )
                            }
                            .contextMenu {
                                Button {
                                    syncService.sendBook(title: book.title, author: book.author, text: book.extractedText)
                                } label: {
                                    Label("Send to Watch", systemImage: "applewatch")
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importer = DocumentImporter(modelContext: modelContext)
                _ = try importer.importFile(at: url)
            } catch {
                importError = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showError = true
        }
    }
}

private struct SendToast: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run existing tests to confirm no regressions**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: All tests pass

**Step 4: Commit**

```bash
git add SpeedRead/Views/LibraryView.swift
git commit -m "feat: redesign LibraryView with bookshelf metaphor and warm palette"
```

---

### Task 7: Redesign ReaderView — Parchment Page

**Files:**
- Modify: `SpeedRead/Views/ReaderView.swift` (full rewrite)

**Step 1: Rewrite ReaderView with parchment styling**

Replace entire content of `ReaderView.swift`:

```swift
//  ReaderView.swift
import SwiftUI

struct ReaderView: View {
    @Bindable var book: Book
    @State private var fontSize: CGFloat = 18
    @State private var showRSVP = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.parchment.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.displayFont(size: 24, weight: .bold))
                        .foregroundStyle(.inkBlack)

                    Text(book.author)
                        .font(.bodySerif(size: 16))
                        .foregroundStyle(.walnutLight)

                    Divider()
                        .background(Color.walnutLight.opacity(0.3))
                        .padding(.vertical, 8)

                    Text(book.extractedText)
                        .font(.bodySerif(size: fontSize))
                        .foregroundStyle(.inkBlack)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            // Bottom toolbar
            HStack {
                HStack(spacing: 12) {
                    Button {
                        fontSize = max(12, fontSize - 2)
                    } label: {
                        Text("A\u{2212}")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.parchment)
                            .frame(width: 36, height: 36)
                            .background(Color.walnutLight, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        fontSize = min(28, fontSize + 2)
                    } label: {
                        Text("A+")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.parchment)
                            .frame(width: 36, height: 36)
                            .background(Color.walnutLight, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Spacer()

                Button {
                    showRSVP = true
                } label: {
                    Text("Start Reading")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.parchment)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.crimsonSoft, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color.walnut
                    .opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.parchment, for: .navigationBar)
        .fullScreenCover(isPresented: $showRSVP) {
            RSVPView(book: book)
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/ReaderView.swift
git commit -m "feat: redesign ReaderView with parchment page styling and serif typography"
```

---

### Task 8: Update RSVPWordView — Warm Colors

**Files:**
- Modify: `SpeedRead/Views/RSVPWordView.swift`

**Step 1: Update RSVPWordView to use theme colors**

Replace hardcoded colors in `RSVPWordView.swift`:

- Change `.foregroundStyle(.secondary)` on before/after text → `.foregroundStyle(.rsvpText.opacity(0.5))`
- Change `.foregroundStyle(.red)` on focus text → `.foregroundStyle(.crimson)`
- Change `.fill(.red)` on guide marks → `.fill(.crimson)`

The full updated file:

```swift
//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat

    init(segments: ORPCalculator.WordSegments, fontSize: CGFloat = 32) {
        self.segments = segments
        self.fontSize = fontSize
    }

    private var font: Font {
        .rsvpWord(size: fontSize)
    }

    private var charWidth: CGFloat {
        fontSize * 0.6
    }

    private let maxSideChars = 12

    var body: some View {
        VStack(spacing: 2) {
            guideMark

            HStack(spacing: 0) {
                Text(segments.before)
                    .font(font)
                    .foregroundStyle(.rsvpText.opacity(0.5))
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .trailing)

                Text(segments.focus)
                    .font(font)
                    .foregroundStyle(.crimson)
                    .frame(width: charWidth, alignment: .center)

                Text(segments.after)
                    .font(font)
                    .foregroundStyle(.rsvpText.opacity(0.5))
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .leading)
            }

            guideMark
        }
        .padding(.horizontal)
    }

    private var guideMark: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
            Rectangle()
                .fill(.crimson)
                .frame(width: 2, height: 8)
                .frame(width: charWidth)
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
        }
        .padding(.horizontal)
    }
}

#Preview("Simple word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "reading"))
        .background(Color.rsvpBackground)
}

#Preview("Short word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "Hi"))
        .background(Color.rsvpBackground)
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "presentation"))
        .background(Color.rsvpBackground)
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run existing tests**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: All tests pass (RSVPWordView is visual only, no logic tests affected)

**Step 4: Commit**

```bash
git add SpeedRead/Views/RSVPWordView.swift
git commit -m "feat: update RSVPWordView with warm crimson and rsvpText colors"
```

---

### Task 9: Redesign RSVPView — Reading by Lamplight

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift` (full rewrite)

**Step 1: Rewrite RSVPView with warm dark theme**

Replace entire content of `RSVPView.swift`:

```swift
//  RSVPView.swift
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Warm dark background with subtle texture
            Color.rsvpBackground
                .ignoresSafeArea()
                .overlay(
                    // Subtle vignette effect
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        center: .center,
                        startRadius: 200,
                        endRadius: 500
                    )
                    .ignoresSafeArea()
                )

            VStack {
                // Header
                HStack {
                    Button {
                        book.lastReadWordIndex = engine.currentIndex
                        engine.stop()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.rsvpText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.walnut.opacity(0.6), in: Capsule())
                    }
                    .frame(minWidth: 44, minHeight: 44)

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Text("\(engine.wpm) WPM")
                            .font(.numeric(size: 14, weight: .medium))
                            .foregroundStyle(.agedGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.walnut.opacity(0.6), in: Capsule())
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(engine.wpm) words per minute, tap to adjust")

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.rsvpText)
                            .padding(10)
                            .background(Color.walnut.opacity(0.6), in: Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Settings")
                }
                .padding()

                // Word display area
                VStack(spacing: 0) {
                    Color.clear
                    RSVPWordView(segments: engine.currentSegments, fontSize: 36)
                    Color.clear
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.togglePlayPause()
                }

                // Bottom controls
                VStack(spacing: 16) {
                    if engine.state != .playing {
                        Button {
                            engine.play()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.crimsonSoft)
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }

                    VStack(spacing: 4) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.walnut)
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [.agedGold.opacity(0.7), .agedGold],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * engine.progress, height: 4)
                                    .animation(.linear(duration: 0.1), value: engine.progress)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text("Word \(engine.currentIndex + 1)")
                            Spacer()
                            Text("of \(engine.totalWords)")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.rsvpText.opacity(0.4))
                        .monospacedDigit()
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.load(words: book.words, startingAt: book.lastReadWordIndex)
        }
        .onDisappear {
            book.lastReadWordIndex = engine.currentIndex
        }
        .sheet(isPresented: $showSettings) {
            wpmSettingsSheet
        }
    }

    private var wpmSettingsSheet: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("\(engine.wpm)")
                        .font(.numeric(size: 64))
                        .foregroundStyle(.agedGold)

                    Text("Words Per Minute")
                        .font(.system(size: 14))
                        .foregroundStyle(.rsvpText.opacity(0.5))

                    Slider(
                        value: Binding(
                            get: { Double(engine.wpm) },
                            set: { engine.wpm = Int($0) }
                        ),
                        in: 100...1000,
                        step: 25
                    )
                    .tint(.agedGold)
                    .padding(.horizontal)

                    HStack {
                        Text("100")
                        Spacer()
                        Text("1000")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.rsvpText.opacity(0.4))
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                    .foregroundStyle(.agedGold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: All tests pass

**Step 4: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "feat: redesign RSVPView with warm lamplight aesthetic and gold accents"
```

---

### Task 10: Redesign Watch — NowReadingView

**Files:**
- Modify: `SpeedReadWatch Watch App/Views/NowReadingView.swift` (full rewrite)

**Step 1: Rewrite NowReadingView with warm palette**

```swift
import SwiftUI

struct NowReadingView: View {
    @EnvironmentObject var syncService: WatchSyncService

    @State private var showRSVP = false

    var body: some View {
        ZStack {
            Color.walnut.ignoresSafeArea()

            Group {
                if syncService.isReceiving, let title = syncService.receivingTitle {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.agedGold)
                        Text("Receiving")
                            .font(.displayFont(size: 16, weight: .semibold))
                            .foregroundStyle(.parchment)
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundStyle(.parchment.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding()
                    .transition(.opacity)
                } else if let title = syncService.lastReceivedBookTitle,
                          syncService.lastReceivedBookText != nil {
                    VStack(spacing: 12) {
                        Text(title)
                            .font(.displayFont(size: 15, weight: .semibold))
                            .foregroundStyle(.parchment)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Button {
                            showRSVP = true
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.crimsonSoft)
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
                            .foregroundStyle(.agedGold)
                        Text("Open your library on iPhone")
                            .font(.displayFont(size: 13, weight: .regular))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.parchment.opacity(0.6))
                    }
                    .padding()
                }
            }
        }
        .animation(.easeInOut, value: syncService.isReceiving)
    }
}
```

**Step 2: Build watch target**

Run: `xcodebuild -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE (44mm)' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/NowReadingView.swift"
git commit -m "feat: redesign Watch NowReadingView with walnut background and warm palette"
```

---

### Task 11: Redesign Watch — WatchRSVPView

**Files:**
- Modify: `SpeedReadWatch Watch App/Views/WatchRSVPView.swift`

**Step 1: Update WatchRSVPView colors**

Replace entire content:

```swift
import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false
    @State private var crownValue: Double = 0

    private var words: [String] {
        (syncService.lastReceivedBookText ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
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
                            syncService.syncReadingPosition(
                                bookTitle: syncService.lastReceivedBookTitle ?? "",
                                wordIndex: engine.currentIndex
                            )
                            engine.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.walnut.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.rsvpText)
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
                            .foregroundStyle(.crimsonSoft)
                    }
                    .buttonStyle(.plain)

                    Text("\(engine.wpm) WPM")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.agedGold)
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
            let w = words
            engine.load(words: w, startingAt: syncService.lastReceivedPosition)
            crownValue = Double(syncService.lastReceivedPosition)
        }
        .onDisappear {
            syncService.syncReadingPosition(
                bookTitle: syncService.lastReceivedBookTitle ?? "",
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

**Step 2: Build watch target**

Run: `xcodebuild -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE (44mm)' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/WatchRSVPView.swift"
git commit -m "feat: redesign WatchRSVPView with warm RSVP colors and walnut buttons"
```

---

### Task 12: Redesign Watch — WatchSettingsView

**Files:**
- Modify: `SpeedReadWatch Watch App/Views/WatchSettingsView.swift`

**Step 1: Update WatchSettingsView colors**

Replace entire content:

```swift
import SwiftUI

struct WatchSettingsView: View {
    var engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @State private var wpmValue: Double = 300

    var body: some View {
        ZStack {
            Color.walnut.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("\(Int(wpmValue))")
                    .font(.numeric(size: 36))
                    .foregroundStyle(.agedGold)

                Text("Words Per Minute")
                    .font(.system(size: 11))
                    .foregroundStyle(.parchment.opacity(0.6))

                Button("Done") {
                    engine.wpm = Int(wpmValue)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.crimsonSoft)
            }
        }
        .focusable()
        .digitalCrownRotation(
            $wpmValue,
            from: 100,
            through: 1000,
            by: 10,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: wpmValue) { _, newValue in
            let snapped = (newValue / 10).rounded() * 10
            if snapped != newValue {
                wpmValue = snapped
            }
        }
        .onAppear {
            wpmValue = (Double(engine.wpm) / 10).rounded() * 10
        }
    }
}
```

**Step 2: Build watch target**

Run: `xcodebuild -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE (44mm)' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add "SpeedReadWatch Watch App/Views/WatchSettingsView.swift"
git commit -m "feat: redesign WatchSettingsView with walnut and gold theme"
```

---

### Task 13: Create OnboardingView

**Files:**
- Create: `SpeedRead/Views/OnboardingView.swift`
- Modify: `SpeedRead/ContentView.swift`

**Step 1: Create OnboardingView**

```swift
//  OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.parchment.ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                rsvpExplanationPage.tag(1)
                getStartedPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(.crimsonSoft)

            Text("Welcome to SpeedRead")
                .font(.displayFont(size: 28, weight: .bold))
                .foregroundStyle(.inkBlack)

            Text("Your cozy reading library")
                .font(.bodySerif(size: 18))
                .foregroundStyle(.walnutLight)

            Spacer()

            nextButton(page: 1)
        }
        .padding(32)
    }

    private var rsvpExplanationPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Static RSVP demo
            VStack(spacing: 2) {
                Rectangle()
                    .fill(Color.crimson)
                    .frame(width: 2, height: 8)

                HStack(spacing: 0) {
                    Text("rea")
                        .foregroundStyle(.walnutLight)
                    Text("d")
                        .foregroundStyle(.crimson)
                    Text("ing")
                        .foregroundStyle(.walnutLight)
                }
                .font(.rsvpWord(size: 36))

                Rectangle()
                    .fill(Color.crimson)
                    .frame(width: 2, height: 8)
            }

            Text("One word at a time")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(.inkBlack)

            Text("The red letter marks where your eye naturally lands, so you read faster with less effort.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(.walnutLight)
                .multilineTextAlignment(.center)

            Spacer()

            nextButton(page: 2)
        }
        .padding(32)
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.agedGold)

            Text("Your shelf is ready")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(.inkBlack)

            Text("We've placed a few classics on your shelf to get started. Import your own PDFs and EPUBs anytime.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(.walnutLight)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                withAnimation {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text("Open Your Library")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.crimsonSoft, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(32)
    }

    private func nextButton(page: Int) -> some View {
        Button {
            withAnimation {
                currentPage = page
            }
        } label: {
            Text("Next")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.crimsonSoft, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
```

**Step 2: Update ContentView to show onboarding on first launch**

Replace entire content of `ContentView.swift`:

```swift
//  ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            LibraryView()
        } else {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
```

**Step 3: Build and verify**

Run: `xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Run all tests**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: All tests pass

**Step 5: Commit**

```bash
git add SpeedRead/Views/OnboardingView.swift SpeedRead/ContentView.swift
git commit -m "feat: add onboarding flow with welcome, RSVP explanation, and library intro"
```

---

### Task 14: Final Integration Test and Polish

**Files:**
- All modified files

**Step 1: Build both targets**

Run iOS:
```bash
xcodebuild -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Run watchOS:
```bash
xcodebuild -scheme "SpeedReadWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch SE (44mm)' build 2>&1 | tail -5
```

Expected: Both BUILD SUCCEEDED

**Step 2: Run full test suite**

```bash
xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: All 63+ tests pass

**Step 3: Visual review in simulator**

Launch the app in the simulator and verify:
- Onboarding shows on first launch (parchment background, serif text, crimson accents)
- Library shows books on wooden shelves after onboarding
- Book spines have varied colors and heights
- ReaderView has parchment page with serif text
- RSVPView has warm dark background with gold progress and crimson ORP
- Watch views have walnut backgrounds with matching warm palette

**Step 4: Fix any build issues or visual polish**

Address any compilation errors or visual inconsistencies found during review.

**Step 5: Final commit if polish changes needed**

```bash
git add -A
git commit -m "polish: final Reading Room design adjustments"
```
