//  RSVPView.swift
import QuartzCore
import SwiftData
import SwiftUI
import os

@MainActor
struct RSVPView: View {
    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "RSVP")

    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: WatchSyncService
    @Environment(\.scenePhase) private var scenePhase

    private let chapters: ChapterNavigation
    @State private var engine: RSVPEngine
    @State private var presentation: RSVPPresentationSession
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = ReaderConfig.RSVP.defaultWPM
    /// The swipe hint shows until the reader has dragged through words once.
    @AppStorage("rsvpHasScrubbed") private var hasScrubbed = false
    /// The word's drawn width, which sets where each neighbor's pivot is on screen.
    @State private var wordWidth: CGFloat = 0
    @State private var scrubDriver = RSVPScrubDriver()
    @State private var showBookmarks = false
    @State private var showHighlights = false
    /// Opened from the reader's "Read here": start playing at once, which takes the book over.
    private let autoplay: Bool

    init(
        book: Book,
        autoplay: Bool = false,
        engine: RSVPEngine? = nil,
        presentation: RSVPPresentationSession? = nil
    ) {
        self.book = book
        self.autoplay = autoplay
        chapters = ChapterNavigation(chapters: book.chapters)
        _engine = State(initialValue: engine ?? RSVPEngine())
        _presentation = State(initialValue: presentation ?? RSVPPresentationSession())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground
                    .ignoresSafeArea()
                    .overlay(
                        RadialGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            center: .center,
                            startRadius: 200,
                            endRadius: 500
                        )
                        .ignoresSafeArea()
                    )

                VStack(spacing: 0) {
                    // ─── ZONE 2: Word Display (fixed center, tappable + scrubable) ───
                    VStack {
                        Spacer(minLength: 0)
                        RSVPWordView(
                            segments: engine.currentSegments,
                            fontSize: Self.wordFontSize,
                            enclosures: engine.currentEnclosures,
                            strip: wordStrip
                        )
                        // Dragged past an end, the line gives a little and springs back.
                        .offset(x: -(presentation.scrub?.stretch ?? 0))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wordWidth = $0 }
                        .overlay(alignment: .bottom) {
                            scrubCaption
                                .offset(y: 40)
                        }
                        .accessibilityHint(engine.state == .playing
                            ? "Double-tap to pause."
                            : "Swipe up or down to move a word. Double-tap to play.")
                        .accessibilityAction { togglePlayback() }
                        .accessibilityAdjustableAction { direction in
                            guard engine.state != .playing, readingElsewhere == nil else { return }
                            let step = direction == .increment ? 1 : direction == .decrement ? -1 : 0
                            engine.seek(to: ReadingPositionCoordinator.clampedIndex(
                                engine.currentIndex + step, wordCount: engine.totalWords))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture, isEnabled: readingElsewhere == nil)

                    // ─── ZONE 3: Control Panel (fixed height) ───
                    ZStack {
                        controlPanel
                            .opacity(readingElsewhere == nil ? 1 : 0)
                            .allowsHitTesting(readingElsewhere == nil)
                            .accessibilityHidden(readingElsewhere != nil)
                        if let presence = readingElsewhere {
                            ReadingElsewhereCard(
                                presence: presence,
                                wordCount: book.wordCount,
                                chapters: book.chapters,
                                background: Color.rsvpBackground,
                                foreground: Color.rsvpText,
                                accent: Color.agedGold,
                                onAccent: Color.rsvpBackground,
                                onReadHere: togglePlayback
                            )
                        }
                    }
                    .frame(height: ReaderConfig.RSVP.controlPanelHeight)
                    .padding(.bottom, ReaderConfig.RSVP.controlPanelBottomPadding)
                    .animation(.easeInOut, value: readingElsewhere)
                }

                // Bookmark flash overlay
                if presentation.feedbackFlash?.kind == .bookmark {
                    Color.agedGold.opacity(0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Highlight flash overlay
                if presentation.feedbackFlash?.kind == .highlight {
                    Color.rsvpText.opacity(0.12)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        let result = presentation.close(
                            engine: engine,
                            book: book,
                            saver: modelContext,
                            sync: syncService
                        )
                        if result?.didSave == false {
                            Self.logger.error("Failed to persist lastReadWordIndex on close")
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.rsvpText)
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(book.title)
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Color.rsvpText.opacity(0.65))
                            .lineLimit(1)
                        if let chapter = chapters.current(at: engine.currentIndex) {
                            Text(chapter.title)
                                .font(.caption)
                                .foregroundStyle(Color.rsvpText.opacity(0.7))
                                .lineLimit(1)
                                .accessibilityLabel("Current chapter: \(chapter.title)")
                                .accessibilityIdentifier("rsvp-current-chapter")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showBookmarks = true
                        } label: {
                            Label("Bookmarks", systemImage: "bookmark")
                        }
                        Button {
                            showHighlights = true
                        } label: {
                            Label("Highlights", systemImage: "highlighter")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.rsvpText)
                    }
                    // Both lists jump, and the other device owns the place while it reads.
                    .disabled(readingElsewhere != nil)
                }
            }
            .toolbarBackground(Color.rsvpBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            presentation.load(book: book, engine: engine, wpm: persistedWPM)
            if autoplay { togglePlayback() }
        }
        // The watch moved the place (crown, chapter, or its live reading): show its word.
        .onChange(of: book.browseWordIndex) { _, index in
            guard engine.state != .playing, index >= 0, index != engine.currentIndex else { return }
            engine.seek(to: index)
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the phone pauses, and the pause hands the book back to the watch.
            if phase == .background, engine.state == .playing { togglePlayback() }
        }
        .onDisappear {
            scrubDriver.stop()
            let result = presentation.handleDisappear(
                engine: engine,
                book: book,
                saver: modelContext,
                sync: syncService
            )
            if result?.didSave == false {
                Self.logger.error("Failed to persist lastReadWordIndex on disappear")
            }
        }
        .onChange(of: engine.didFinish) { _, didFinish in
            guard didFinish else { return }
            let result = presentation.commitPlaybackAdvanceIfNeeded(
                engine: engine,
                book: book,
                saver: modelContext,
                sync: syncService
            )
            if result?.didSave == false {
                Self.logger.error("Failed to persist RSVP completion")
            }
        }
        .onChange(of: engine.currentIndex) { _, newIndex in
            if engine.state == .playing {
                let result = presentation.commitPlaybackAdvanceIfNeeded(
                    engine: engine,
                    book: book,
                    saver: modelContext,
                    sync: syncService
                )
                if result?.didSave == false {
                    Self.logger.error("Failed to persist throttled RSVP reading position")
                }
            } else if !presentation.recordBrowsePosition(
                newIndex,
                book: book,
                saver: modelContext,
                sync: syncService
            ) {
                Self.logger.error("Failed to persist local RSVP browse position")
            }
        }
        .task(id: presentation.feedbackFlash?.id) {
            guard let flash = presentation.feedbackFlash else { return }
            do {
                try await Task.sleep(for: ReaderConfig.RSVP.feedbackFlashDuration)
            } catch {
                return
            }
            withAnimation(.easeIn(duration: ReaderConfig.RSVP.feedbackFadeDuration)) {
                presentation.clearFeedback(flash)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListView(book: book, engine: engine)
        }
        .sheet(isPresented: $showHighlights) {
            HighlightListView(book: book, engine: engine)
        }
    }

    // MARK: - Zone 3: Control Panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            wpmControls

            actionButtons

            progressSection
        }
        .padding(.horizontal)
    }

    private var wpmControls: some View {
        HStack(spacing: 20) {
            Button {
                engine.wpm -= ReaderConfig.RSVP.wpmStep
                persistedWPM = engine.wpm
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.rsvpText.opacity(0.75))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Decrease speed by 25 words per minute")

            Text("\(engine.wpm) WPM")
                .font(.numeric(size: 18, weight: .medium))
                .foregroundStyle(Color.agedGold)
                .frame(minWidth: 100)
                .accessibilityLabel("\(engine.wpm) words per minute")

            Button {
                engine.wpm += ReaderConfig.RSVP.wpmStep
                persistedWPM = engine.wpm
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.rsvpText.opacity(0.75))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Increase speed by 25 words per minute")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            RSVPPlaybackControl(isPlaying: engine.state == .playing) {
                togglePlayback()
            }
            .font(.system(size: 44))
            .foregroundStyle(Color.agedGold)
            .frame(minWidth: 44, minHeight: 44)

            Button {
                addBookmark()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.agedGold)
                    .padding(10)
                    .background(Color.rsvpText.opacity(0.14), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .opacity(engine.state != .playing ? 1 : 0)
            .allowsHitTesting(engine.state != .playing)

            Button {
                toggleHighlight()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                    Text(presentation.highlightStartIndex != nil ? "Stop" : "Highlight")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(presentation.highlightStartIndex != nil ? Color.rsvpBackground : Color.rsvpText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    presentation.highlightStartIndex != nil ? Color.agedGold : Color.rsvpText.opacity(0.14),
                    in: Capsule()
                )
            }
            .frame(minHeight: 44)
            .opacity(engine.state != .playing ? 1 : 0)
            .allowsHitTesting(engine.state != .playing)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rsvpText.opacity(0.18))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.agedGold.opacity(0.7), Color.agedGold],
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
            .foregroundStyle(Color.rsvpText.opacity(0.65))
            .monospacedDigit()
        }
    }

    // MARK: - Scrub Gesture

    /// The line of words around the current one while dragging, so the drag reads as moving text.
    private var wordStrip: RSVPWordStrip {
        guard engine.state != .playing else { return .hidden }
        return RSVPWordStrip(
            words: presentation.cachedWords,
            index: engine.currentIndex,
            offset: presentation.scrub?.offset ?? 0,
            opacity: presentation.scrub?.opacity ?? 0
        )
    }

    private static let wordFontSize: CGFloat = 36
    private static let characterAdvance = RSVPScrubTrack.characterAdvance(fontSize: wordFontSize)

    /// Where each word sits on screen, so the line moves exactly with the finger.
    private var scrubTrack: RSVPScrubTrack {
        RSVPScrubTrack(
            words: presentation.cachedWords,
            advance: Self.characterAdvance,
            availableWidth: wordWidth - 2 * RSVPWordView.horizontalPadding
        )
    }

    /// While dragging: how far, and which way. Before the first drag: how to.
    @ViewBuilder
    private var scrubCaption: some View {
        if let scrub = presentation.scrub {
            if let text = RSVPScrubCaption.text(from: scrub.startIndex, to: engine.currentIndex) {
                let direction = RSVPScrubCaption.direction(from: scrub.startIndex, to: engine.currentIndex)
                HStack(spacing: 4) {
                    if direction == .back { Image(systemName: "chevron.backward") }
                    Text(text)
                    if direction == .ahead { Image(systemName: "chevron.forward") }
                }
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.agedGold)
                .opacity(scrub.opacity)
                .accessibilityHidden(true)
            }
        } else if !hasScrubbed, engine.state != .playing, readingElsewhere == nil {
            Text("Drag right to go back, left to go ahead · Tap to play")
                .font(.system(size: 13))
                .foregroundStyle(Color.rsvpText.opacity(0.7))
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if presentation.scrub == nil { scrubDriver.prepareHaptics() }
                apply(presentation.updateGesture(
                    translationX: value.translation.width,
                    at: CACurrentMediaTime(),
                    isPlaying: engine.state == .playing,
                    currentIndex: engine.currentIndex,
                    wordCount: engine.totalWords,
                    track: scrubTrack
                ))
            }
            .onEnded { _ in
                let track = scrubTrack
                let interaction = presentation.endGesture(at: CACurrentMediaTime(), track: track)
                if interaction == .togglePlayback {
                    togglePlayback()
                }
                guard presentation.isAnimating else { return }
                scrubDriver.run { now in
                    apply(presentation.advance(at: now, track: track))
                    return presentation.isAnimating
                }
            }
    }

    private func apply(_ update: RSVPScrubUpdate?) {
        guard let update else { return }
        if update.wordDelta != 0 {
            engine.seek(to: update.targetIndex)
            if !hasScrubbed { hasScrubbed = true }
        }
        if let haptic = update.haptic { scrubDriver.play(haptic) }
    }

    // MARK: - Actions

    private var readingElsewhere: RemotePresence? {
        syncService.remotePresence(for: book.id)
    }

    private func togglePlayback() {
        let result = presentation.togglePlayback(
            engine: engine,
            book: book,
            saver: modelContext,
            sync: syncService
        )
        if result?.didSave == false {
            Self.logger.error("Failed to persist RSVP play position")
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func addBookmark() {
        presentation.addBookmark(at: engine.currentIndex, book: book, modelContext: modelContext)

        withAnimation(.easeOut(duration: ReaderConfig.RSVP.feedbackFadeDuration)) {
            _ = presentation.requestFeedback(.bookmark)
        }
    }

    private func toggleHighlight() {
        guard presentation.toggleHighlight(
            at: engine.currentIndex, book: book, modelContext: modelContext
        ) else { return }

        withAnimation(.easeOut(duration: ReaderConfig.RSVP.feedbackFadeDuration)) {
            _ = presentation.requestFeedback(.highlight)
        }
    }
}

/// Runs the scrub's motion after the finger lifts on the display's frames, and plays its haptics:
/// a tick for each word that reaches the guides, a knock at either end of the book.
@MainActor
private final class RSVPScrubDriver: NSObject {
    private var link: CADisplayLink?
    private var onFrame: ((TimeInterval) -> Bool)?
    private let tick = UISelectionFeedbackGenerator()
    private let knock = UIImpactFeedbackGenerator(style: .rigid)

    func prepareHaptics() {
        tick.prepare()
        knock.prepare()
    }

    func play(_ haptic: RSVPScrubHaptic) {
        switch haptic {
        case .word:
            tick.selectionChanged()
            tick.prepare()
        case .edge:
            knock.impactOccurred()
        }
    }

    /// Calls `onFrame` with each frame's time until it returns false.
    func run(_ onFrame: @escaping (TimeInterval) -> Bool) {
        self.onFrame = onFrame
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        if onFrame?(link.targetTimestamp) != true { stop() }
    }
}
