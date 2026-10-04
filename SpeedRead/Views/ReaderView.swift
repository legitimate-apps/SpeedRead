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
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("readerFontSize") private var fontSize: Double = ReaderConfig.Classic.defaultFontSize
    @AppStorage("readerLineSpacing") private var lineSpacingPref: Double = ReaderConfig.Classic.defaultLineSpacing
    @AppStorage("readerThemeMode") private var themeMode: String = ReaderThemeMode.parchment.rawValue
    @AppStorage("rsvpLastWPM") private var lastWPM: Int = ReaderConfig.RSVP.defaultWPM

    @State private var session: ReaderSession
    @State private var rsvpLaunch: RSVPLaunch?
    @State private var showChapters = false
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
                            paragraphList(scrollProxy: scrollProxy)
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
                    guard let target = newValue,
                          let paragraph = session.paragraphAnchorID(for: target) else { return }
                    withAnimation(.easeInOut(duration: ReaderConfig.Classic.scrollAnimationDuration)) {
                        scrollProxy.scrollTo(paragraph, anchor: .center)
                    }
                }
                // Once paragraphs have been laid out, scroll to the last-read word.
                // Triggered by the cachedWords flip from empty → loaded, which
                // happens after the layout pass — no asyncAfter race.
                .task(id: session.cachedWords.count) {
                    guard !session.cachedWords.isEmpty else { return }
                    session.requestInitialScroll(for: book)
                }
            }

            if let presence = readingElsewhere {
                ReadingElsewhereCard(
                    presence: presence,
                    wordCount: book.wordCount,
                    chapters: book.chapters,
                    background: currentTheme.background,
                    foreground: currentTheme.bodyText,
                    accent: currentTheme.accent,
                    onAccent: currentTheme.onAccent,
                    onReadHere: {
                        rsvpLaunch = RSVPLaunch(autoplay: true)
                    }
                )
                .padding(.bottom, 8)
            } else {
                bottomBar
            }
        }
        .animation(.easeInOut, value: readingElsewhere)
        // The place moved on the watch, or the watch is reading: keep its word in view.
        .onChange(of: book.browseWordIndex) { _, _ in
            guard rsvpLaunch == nil, session.wordFlash == nil else { return }
            session.reconcileRSVPDismiss(for: book)
        }
        .overlay(alignment: .top) {
            if let offer = serverSync.pendingOffer, offer.bookId == book.id {
                ServerPositionOfferBanner(
                    offer: offer,
                    palette: currentTheme,
                    onContinue: {
                        if serverSync.accept(offer, sync: syncService) {
                            session.requestInitialScroll(for: book)
                        }
                    },
                    onDismiss: { serverSync.decline(offer) }
                )
            }
        }
        .animation(.easeInOut, value: serverSync.pendingOffer)
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
                        .foregroundStyle(currentTheme.headerText.opacity(0.7))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !book.chapters.isEmpty {
                        Button {
                            showChapters = true
                        } label: { Label("Chapters", systemImage: "list.bullet") }
                        .accessibilityLabel("Chapters")
                    }
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
                .accessibilityLabel("Reader menu")
            }
        }
        .task {
            session.load(book: book)
            #if DEBUG
            // Screenshot hooks: auto-present RSVP or one of the reader sheets so scripted
            // captures can reach them without driving the menu.
            if ProcessInfo.processInfo.arguments.contains("--auto-open-rsvp") {
                try? await Task.sleep(for: .milliseconds(800))
                rsvpLaunch = RSVPLaunch()
            } else if let sheetFlag = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("--auto-open-reader-sheet=")
            }) {
                try? await Task.sleep(for: .milliseconds(800))
                switch sheetFlag.components(separatedBy: "=").last {
                case "settings": showSettings = true
                case "chapters": showChapters = true
                case "bookmarks": showBookmarks = true
                case "highlights": showHighlights = true
                default: break
                }
            }
            #endif
        }
        .task(id: book.id) {
            await serverSync.pull(bookId: book.id)
            await ServerAnnotationSync.shared.sync(bookId: book.id)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await serverSync.pull(bookId: book.id)
                await ServerAnnotationSync.shared.sync(bookId: book.id)
            }
        }
        .onDisappear {
            serverSync.dismissOffer(for: book.id)
            Task {
                await serverSync.flush()
                await ServerAnnotationSync.shared.flush()
            }
        }
        .task(id: session.wordFlash?.id) {
            guard let flash = session.wordFlash else { return }
            do {
                try await Task.sleep(for: ReaderConfig.Classic.rsvpTransitionDelay)
            } catch {
                return
            }
            guard session.wordFlash == flash else { return }
            rsvpLaunch = RSVPLaunch()
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
        .fullScreenCover(item: $rsvpLaunch, onDismiss: {
            rsvpDismissGeneration += 1
        }) { launch in
            RSVPView(book: book, autoplay: launch.autoplay)
        }
        .sheet(isPresented: $showChapters) {
            ReaderChapterPicker(chapters: ChapterNavigation(chapters: book.chapters),
                                wordIndex: book.browseWordIndex,
                                palette: currentTheme) { index in
                browse(to: index)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            ReaderBookmarkPicker(book: book, palette: currentTheme) { index in
                browse(to: index)
            }
        }
        .sheet(isPresented: $showHighlights) {
            ReaderHighlightPicker(book: book, palette: currentTheme) { index in
                browse(to: index)
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(
                fontSize: $fontSize,
                lineSpacing: $lineSpacingPref,
                themeMode: $themeMode,
                palette: currentTheme
            )
        }
    }

    private var serverSync: ServerPositionSync { .shared }

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

    private func paragraphList(scrollProxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: lineSpacingPref + 8) {
            ForEach(session.paragraphs) { paragraph in
                paragraphView(paragraph)
                    .id(paragraph.id)
                    .task(id: session.pendingScrollIndex) {
                        guard let target = session.pendingScrollIndex,
                              session.paragraphAnchorID(for: target) == paragraph.id else { return }
                        // This task only runs after the lazy paragraph is mounted, so its
                        // word anchors now exist. No delay guesses for layout timing.
                        scrollProxy.scrollTo(session.scrollAnchorID(for: target), anchor: .center)
                        _ = session.consumePendingScroll()
                    }
            }
        }
    }

    private func paragraphView(_ paragraph: ReaderParagraph) -> some View {
        WordFlowLayout(hSpacing: 2, vSpacing: CGFloat(lineSpacingPref)) {
            ForEach(Array(paragraph.words.enumerated()), id: \.offset) { offset, word in
                let absoluteIndex = paragraph.startIndex + offset
                let isLastRead = absoluteIndex == clampedPlaceIndex
                let isFlashed = absoluteIndex == session.wordFlash?.wordIndex
                let highlighted = isLastRead || isFlashed
                let displayText = word + " "
                Button {
                    handleWordTap(at: absoluteIndex)
                } label: {
                    Text(displayText)
                        .font(.system(size: fontSize, weight: highlighted ? .bold : .regular, design: .serif))
                        .foregroundStyle(highlighted ? currentTheme.pivot : currentTheme.bodyText)
                        .padding(.horizontal, 1)
                        .background(
                            highlighted
                                ? currentTheme.pivot.opacity(isFlashed ? 0.28 : 0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .scaleEffect(isFlashed ? 1.06 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isFlashed)
                }
                .buttonStyle(.plain)
                // While the watch reads, only the card's "Read here" moves the book on.
                .disabled(readingElsewhere != nil)
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
                rsvpLaunch = RSVPLaunch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("RSVP")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(currentTheme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(currentTheme.accent, in: Capsule())
            }
            .accessibilityLabel("Start RSVP from current word")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            currentTheme.barBackground
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func iconBarButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
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

    /// The red word: the place, shared live with the watch.
    private var clampedPlaceIndex: Int {
        session.clampedIndex(book.browseWordIndex)
    }

    private var readingElsewhere: RemotePresence? {
        syncService.remotePresence(for: book.id)
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

    private func browse(to index: Int) {
        if !session.browse(to: index, book: book, saver: modelContext, sync: syncService) {
            Self.logger.error("Failed to persist reader browse position")
        }
    }

    private func cycleTheme() {
        themeMode = session.cycleTheme(from: themeMode)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct ServerPositionOfferBanner: View {
    let offer: ServerPositionSync.Offer
    let palette: ReaderPalette
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(offer.displayText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.bodyText)
            if !offer.snippet.isEmpty {
                Text(offer.snippet)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(palette.bodyText.opacity(0.75))
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .accessibilityIdentifier("server-position-offer-continue")
                Button("Stay Here", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                    .accessibilityIdentifier("server-position-offer-dismiss")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque: the bar colour is translucent, and the page text showing through made the
        // offer hard to read (observed on the CWNG end-to-end run, 2026-10-03).
        .background(palette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.barText.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("server-position-offer")
    }
}

/// One presentation of RSVP. The autoplay flag travels with the presentation: a separate
/// `@State` read only inside the cover's closure reached RSVP stale, so "Read here" opened it
/// paused and the watch kept the book.
private struct RSVPLaunch: Identifiable {
    let id = UUID()
    var autoplay = false
}
