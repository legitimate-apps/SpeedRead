//  ReaderView.swift
import SwiftUI
import SwiftData

struct ReaderView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext

    @AppStorage("readerFontSize") private var fontSize: Double = 18
    @AppStorage("readerLineSpacing") private var lineSpacingPref: Double = 6
    @AppStorage("readerThemeMode") private var themeMode: String = ReaderThemeMode.parchment.rawValue
    @AppStorage("rsvpLastWPM") private var lastWPM: Int = 300

    @State private var showRSVP = false
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var showSettings = false
    @State private var pendingScrollIndex: Int?
    @State private var cachedWords: [String] = []
    @State private var paragraphs: [ReaderParagraph] = []
    @State private var flashedWordIndex: Int?

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTheme.background.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if !cachedWords.isEmpty {
                            paragraphList
                        } else {
                            ProgressView()
                                .padding(.top, 80)
                                .frame(maxWidth: .infinity)
                        }

                        Color.clear.frame(height: 140)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                }
                .onChange(of: pendingScrollIndex) { _, newValue in
                    guard let target = newValue else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        scrollProxy.scrollTo(scrollAnchorID(for: target), anchor: .center)
                    }
                    pendingScrollIndex = nil
                }
                // Once paragraphs have been laid out, scroll to the last-read word.
                // Triggered by the cachedWords flip from empty → loaded, which
                // happens after the layout pass — no asyncAfter race.
                .task(id: cachedWords.count) {
                    guard !cachedWords.isEmpty else { return }
                    pendingScrollIndex = clampedLastReadIndex
                }
            }

            bottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(currentTheme.barBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(currentTheme.toolbarColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(currentTheme.headerText)
                        .lineLimit(1)
                    Text(headerSubtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(currentTheme.headerText.opacity(0.55))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showBookmarks = true
                    } label: { Label("Bookmarks", systemImage: "bookmark") }
                    Button {
                        showHighlights = true
                    } label: { Label("Highlights", systemImage: "highlighter") }
                    Divider()
                    Button {
                        showSettings = true
                    } label: { Label("Reader Settings", systemImage: "textformat") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(currentTheme.accent)
                }
            }
        }
        .task {
            await loadWordsIfNeeded()
        }
        .fullScreenCover(isPresented: $showRSVP, onDismiss: handleRSVPDismiss) {
            RSVPView(book: book)
        }
        .sheet(isPresented: $showBookmarks) {
            ReaderBookmarkPicker(book: book) { index in
                book.lastReadWordIndex = index
                pendingScrollIndex = index
            }
        }
        .sheet(isPresented: $showHighlights) {
            ReaderHighlightPicker(book: book) { index in
                book.lastReadWordIndex = index
                pendingScrollIndex = index
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(
                fontSize: $fontSize,
                lineSpacing: $lineSpacingPref,
                themeMode: $themeMode
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(currentTheme.titleText)

            Text(book.author)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(currentTheme.bodyText.opacity(0.65))

            Rectangle()
                .fill(currentTheme.bodyText.opacity(0.18))
                .frame(height: 1)
                .padding(.top, 6)
        }
    }

    private var paragraphList: some View {
        LazyVStack(alignment: .leading, spacing: lineSpacingPref + 8) {
            ForEach(paragraphs) { paragraph in
                paragraphView(paragraph)
                    .id(paragraph.id)
            }
        }
    }

    private func paragraphView(_ paragraph: ReaderParagraph) -> some View {
        WordFlowLayout(hSpacing: 2, vSpacing: CGFloat(lineSpacingPref)) {
            ForEach(Array(paragraph.words.enumerated()), id: \.offset) { offset, word in
                let absoluteIndex = paragraph.startIndex + offset
                let isLastRead = absoluteIndex == clampedLastReadIndex
                let isFlashed = absoluteIndex == flashedWordIndex
                let highlighted = isLastRead || isFlashed
                let displayText = word + " "
                Button {
                    handleWordTap(at: absoluteIndex)
                } label: {
                    Text(displayText)
                        .font(.system(size: fontSize, weight: highlighted ? .bold : .regular, design: .serif))
                        .foregroundStyle(highlighted ? Color.crimson : currentTheme.bodyText)
                        .padding(.horizontal, 1)
                        .background(
                            highlighted
                                ? Color.crimson.opacity(isFlashed ? 0.28 : 0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .scaleEffect(isFlashed ? 1.06 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isFlashed)
                }
                .buttonStyle(.plain)
                .id(scrollAnchorID(for: absoluteIndex))
                .accessibilityLabel(Text(word))
                .accessibilityHint(Text("Start RSVP from this word"))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            iconBarButton(systemName: "textformat.size.smaller", label: "Decrease font size") {
                fontSize = max(12, fontSize - 2)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            iconBarButton(systemName: "textformat.size.larger", label: "Increase font size") {
                fontSize = min(34, fontSize + 2)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            iconBarButton(systemName: "moon.stars", label: "Cycle reading theme") {
                cycleTheme()
            }

            Spacer(minLength: 6)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pendingScrollIndex = clampedLastReadIndex
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(currentTheme.barText)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().stroke(currentTheme.barText.opacity(0.3), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Resume — jump to the last-read word")

            Button {
                showRSVP = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("RSVP")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.crimson, in: Capsule())
            }
            .accessibilityLabel("Start RSVP from current word")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            currentTheme.barBackground
                .opacity(0.96)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func iconBarButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(currentTheme.barText)
                .frame(width: 38, height: 38)
        }
        .accessibilityLabel(label)
    }

    // MARK: - State + actions

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : 22
        #else
        22
        #endif
    }

    private var clampedLastReadIndex: Int {
        guard !cachedWords.isEmpty else { return 0 }
        return min(max(0, book.lastReadWordIndex), cachedWords.count - 1)
    }

    private var headerSubtitle: String {
        let percent = Int(book.progress * 100)
        let remainingWords = max(0, book.wordCount - book.lastReadWordIndex)
        let wpm = max(60, lastWPM)
        let minutes = Int((Double(remainingWords) / Double(wpm)).rounded())
        if remainingWords == 0 {
            return "\(percent)% · finished"
        }
        if minutes <= 0 {
            return "\(percent)% · <1 min left at \(wpm) WPM"
        }
        return "\(percent)% · \(minutes) min left at \(wpm) WPM"
    }

    private var currentTheme: ReaderPalette {
        ReaderThemeMode(rawValue: themeMode)?.palette ?? ReaderThemeMode.parchment.palette
    }

    private func scrollAnchorID(for index: Int) -> String {
        "word-\(index)"
    }

    private func handleWordTap(at index: Int) {
        let clamped = max(0, min(index, max(0, cachedWords.count - 1)))
        book.lastReadWordIndex = clamped
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        flashedWordIndex = clamped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showRSVP = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if flashedWordIndex == clamped {
                flashedWordIndex = nil
            }
        }
    }

    private func handleRSVPDismiss() {
        // RSVP already wrote `lastReadWordIndex` on close. Trigger a scroll so the
        // newly-highlighted word is centered when the reader reappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pendingScrollIndex = clampedLastReadIndex
        }
    }

    private func cycleTheme() {
        let modes = ReaderThemeMode.allCases
        let current = ReaderThemeMode(rawValue: themeMode) ?? .parchment
        let next = modes[(modes.firstIndex(of: current).map { ($0 + 1) % modes.count }) ?? 0]
        themeMode = next.rawValue
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func loadWordsIfNeeded() async {
        guard cachedWords.isEmpty else { return }
        book.ensureTokensCached()
        let extractedText = book.extractedText
        let words = book.words
        let para = ReaderParagraphizer.paragraphs(from: extractedText, allWords: words)
        await MainActor.run {
            self.cachedWords = words
            self.paragraphs = para
        }
    }
}

// MARK: - Reader theme palettes

enum ReaderThemeMode: String, CaseIterable {
    case parchment
    case sepia
    case night

    var palette: ReaderPalette {
        switch self {
        case .parchment:
            return ReaderPalette(
                background: Color.parchment,
                titleText: Color.inkBlack,
                bodyText: Color.inkBlack.opacity(0.92),
                headerText: Color.inkBlack.opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color.parchment.opacity(0.92),
                barText: Color.inkBlack.opacity(0.78),
                toolbarColorScheme: .light
            )
        case .sepia:
            return ReaderPalette(
                background: Color(red: 0xF7 / 255, green: 0xEB / 255, blue: 0xCF / 255),
                titleText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255),
                bodyText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.92),
                headerText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color(red: 0xF1 / 255, green: 0xE3 / 255, blue: 0xC2 / 255).opacity(0.94),
                barText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.8),
                toolbarColorScheme: .light
            )
        case .night:
            return ReaderPalette(
                background: Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x12 / 255),
                titleText: Color(red: 0xF1 / 255, green: 0xEC / 255, blue: 0xDD / 255),
                bodyText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.92),
                headerText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255).opacity(0.94),
                barText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.85),
                toolbarColorScheme: .dark
            )
        }
    }
}

struct ReaderPalette {
    let background: Color
    let titleText: Color
    let bodyText: Color
    let headerText: Color
    let accent: Color
    let barBackground: Color
    let barText: Color
    let toolbarColorScheme: ColorScheme
}

// MARK: - Settings sheet

private struct ReaderSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var themeMode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Typography") {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $fontSize, in: 12...34, step: 1)

                    HStack {
                        Text("Line spacing")
                        Spacer()
                        Text("\(Int(lineSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $lineSpacing, in: 2...18, step: 1)
                }

                Section("Theme") {
                    Picker("Reading theme", selection: $themeMode) {
                        ForEach(ReaderThemeMode.allCases, id: \.rawValue) { mode in
                            Text(mode.rawValue.capitalized).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Reader Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ReaderBookmarkPicker: View {
    let book: Book
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if book.bookmarks.isEmpty {
                    Text("No bookmarks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(book.bookmarks.sorted(by: { $0.wordIndex < $1.wordIndex }), id: \.id) { bookmark in
                        Button {
                            onSelect(bookmark.wordIndex)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.previewText)
                                    .font(.system(size: 15, design: .serif))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("Word \(bookmark.wordIndex + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct ReaderHighlightPicker: View {
    let book: Book
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if book.highlights.isEmpty {
                    Text("No highlights yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(book.highlights.sorted(by: { $0.startWordIndex < $1.startWordIndex }), id: \.id) { highlight in
                        Button {
                            onSelect(highlight.startWordIndex)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlight.highlightedText)
                                    .font(.system(size: 15, design: .serif))
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                Text("Words \(highlight.startWordIndex + 1)–\(highlight.endWordIndex + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Highlights")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
