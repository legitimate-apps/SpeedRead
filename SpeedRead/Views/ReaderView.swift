//  ReaderView.swift
import SwiftData
import SwiftUI
import os

@MainActor
struct ReaderView: View {
    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "Reader")

    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: WatchSyncService

    @AppStorage("readerFontSize") private var fontSize: Double = ReaderConfig.Classic.defaultFontSize
    @AppStorage("readerLineSpacing") private var lineSpacingPref: Double = ReaderConfig.Classic.defaultLineSpacing
    @AppStorage("readerThemeMode") private var themeMode: String = ReaderThemeMode.parchment.rawValue
    @AppStorage("rsvpLastWPM") private var lastWPM: Int = ReaderConfig.RSVP.defaultWPM

    @State private var session: ReaderSession
    @State private var showRSVP = false
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var showSettings = false
    @State private var rsvpDismissGeneration = 0

    init(book: Book, session: ReaderSession? = nil) {
        self.book = book
        _session = State(initialValue: session ?? ReaderSession())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTheme.background.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if !session.cachedWords.isEmpty {
                            paragraphList
                        } else {
                            ProgressView()
                                .padding(.top, 80)
                                .frame(maxWidth: .infinity)
                        }

                        Color.clear.frame(height: ReaderConfig.Classic.bottomContentInset)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                }
                .onChange(of: session.pendingScrollIndex) { _, newValue in
                    guard let target = newValue else { return }
                    withAnimation(.easeInOut(duration: ReaderConfig.Classic.scrollAnimationDuration)) {
                        scrollProxy.scrollTo(session.scrollAnchorID(for: target), anchor: .center)
                    }
                    _ = session.consumePendingScroll()
                }
                // Once paragraphs have been laid out, scroll to the last-read word.
                // Triggered by the cachedWords flip from empty → loaded, which
                // happens after the layout pass — no asyncAfter race.
                .task(id: session.cachedWords.count) {
                    guard !session.cachedWords.isEmpty else { return }
                    session.requestInitialScroll(for: book)
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
            session.load(book: book)
        }
        .task(id: session.wordFlash?.id) {
            guard let flash = session.wordFlash else { return }
            do {
                try await Task.sleep(for: ReaderConfig.Classic.rsvpTransitionDelay)
            } catch {
                return
            }
            guard session.wordFlash == flash else { return }
            showRSVP = true
        }
        .task(id: session.wordFlash?.id) {
            guard let flash = session.wordFlash else { return }
            do {
                try await Task.sleep(for: ReaderConfig.Classic.wordFlashDuration)
            } catch {
                return
            }
            session.clearWordFlash(flash)
        }
        .task(id: rsvpDismissGeneration) {
            guard rsvpDismissGeneration > 0 else { return }
            await Task.yield()
            session.reconcileRSVPDismiss(for: book)
        }
        .fullScreenCover(isPresented: $showRSVP, onDismiss: {
            rsvpDismissGeneration += 1
        }) {
            RSVPView(book: book)
        }
        .sheet(isPresented: $showBookmarks) {
            ReaderBookmarkPicker(book: book) { index in
                commitReadingPosition(index)
                session.reconcileRSVPDismiss(for: book)
            }
        }
        .sheet(isPresented: $showHighlights) {
            ReaderHighlightPicker(book: book) { index in
                commitReadingPosition(index)
                session.reconcileRSVPDismiss(for: book)
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
            ForEach(session.paragraphs) { paragraph in
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
                let isFlashed = absoluteIndex == session.wordFlash?.wordIndex
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
                .id(session.scrollAnchorID(for: absoluteIndex))
                .accessibilityLabel(Text(word))
                .accessibilityHint(Text("Start RSVP from this word"))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            iconBarButton(systemName: "textformat.size.smaller", label: "Decrease font size") {
                fontSize = max(ReaderConfig.Classic.fontSizeRange.lowerBound, fontSize - ReaderConfig.Classic.fontSizeStep)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            iconBarButton(systemName: "textformat.size.larger", label: "Increase font size") {
                fontSize = min(ReaderConfig.Classic.fontSizeRange.upperBound, fontSize + ReaderConfig.Classic.fontSizeStep)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            iconBarButton(systemName: "moon.stars", label: "Cycle reading theme") {
                cycleTheme()
            }

            Spacer(minLength: 6)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                session.reconcileRSVPDismiss(for: book)
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
        UIDevice.current.userInterfaceIdiom == .pad
            ? ReaderConfig.Classic.padHorizontalPadding
            : ReaderConfig.Classic.phoneHorizontalPadding
        #else
        ReaderConfig.Classic.phoneHorizontalPadding
        #endif
    }

    private var clampedLastReadIndex: Int {
        session.clampedIndex(book.lastReadWordIndex)
    }

    private var headerSubtitle: String {
        Self.readingEstimate(book: book, lastWPM: lastWPM)
    }

    static func readingEstimate(book: Book, lastWPM: Int) -> String {
        let percent = Int(book.progress * 100)
        let remainingWords = max(0, book.wordCount - book.lastReadWordIndex)
        let wpm = max(ReaderConfig.RSVP.minimumEstimateWPM, lastWPM)
        let minutes = Int((Double(remainingWords) / Double(wpm)).rounded())
        if book.wordCount > 0 && book.finishedAt != nil {
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

    private func handleWordTap(at index: Int) {
        let outcome = session.handleWordTap(
            at: index,
            book: book,
            saver: modelContext,
            sync: syncService
        )
        if !outcome.commit.didSave {
            Self.logger.error("Failed to persist lastReadWordIndex")
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func commitReadingPosition(_ index: Int) {
        let result = session.commitReadingPosition(
            index,
            book: book,
            saver: modelContext,
            sync: syncService
        )
        if !result.didSave {
            Self.logger.error("Failed to persist lastReadWordIndex")
        }
    }

    private func cycleTheme() {
        themeMode = session.cycleTheme(from: themeMode)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
