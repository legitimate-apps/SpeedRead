//  RSVPView.swift
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

    private let chapters: ChapterNavigation
    @State private var engine: RSVPEngine
    @State private var presentation: RSVPPresentationSession
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = ReaderConfig.RSVP.defaultWPM
    @State private var showBookmarks = false
    @State private var showHighlights = false

    init(
        book: Book,
        engine: RSVPEngine? = nil,
        presentation: RSVPPresentationSession? = nil
    ) {
        self.book = book
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
                        RSVPWordView(segments: engine.currentSegments, fontSize: 36)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture)

                    // ─── ZONE 3: Control Panel (fixed height) ───
                    controlPanel
                        .frame(height: ReaderConfig.RSVP.controlPanelHeight)
                        .padding(.bottom, ReaderConfig.RSVP.controlPanelBottomPadding)
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
                }
            }
            .toolbarBackground(Color.rsvpBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            presentation.load(book: book, engine: engine, wpm: persistedWPM)
        }
        .onDisappear {
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
                saver: modelContext
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

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let update = presentation.updateGesture(
                    translationX: value.translation.width,
                    isPlaying: engine.state == .playing,
                    currentIndex: engine.currentIndex,
                    wordCount: engine.totalWords
                ) {
                    engine.seek(to: update.targetIndex)
                    if update.shouldProduceHaptic {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                if presentation.endGesture() == .togglePlayback {
                    togglePlayback()
                }
            }
    }

    // MARK: - Actions

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
