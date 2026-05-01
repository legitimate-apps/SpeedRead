//  RSVPView.swift
import SwiftData
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var engine = RSVPEngine()
    @State private var cachedWords: [String] = []
    @State private var highlightStartIndex: Int?
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = 300
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var bookmarkFlash = false
    @State private var highlightFlash = false

    // Scrub gesture state
    @State private var lastDragX: CGFloat = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var lastDragTime: Date = .now
    @State private var dragVelocity: CGFloat = 0

    private let basePtsPerWord: CGFloat = 8
    private let maxVelocityMultiplier: CGFloat = 50
    private let hapticInterval = 10

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
                    .onTapGesture {
                        engine.togglePlayPause()
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    .gesture(scrubGesture)

                    // ─── ZONE 3: Control Panel (fixed height) ───
                    controlPanel
                        .frame(height: 160)
                        .padding(.bottom, 20)
                }

                // Bookmark flash overlay
                if bookmarkFlash {
                    Color.agedGold.opacity(0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Highlight flash overlay
                if highlightFlash {
                    Color.crimson.opacity(0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        let index = engine.snapshotIndexAndPause()
                        book.lastReadWordIndex = index
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
                    Text(book.title)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(Color.rsvpText.opacity(0.4))
                        .lineLimit(1)
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
            book.ensureTokensCached()
            cachedWords = book.words
            engine.wpm = persistedWPM
            engine.load(words: cachedWords, startingAt: book.lastReadWordIndex)
        }
        .onDisappear {
            if engine.isLoaded {
                book.lastReadWordIndex = engine.currentIndex
            }
            engine.stop()
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
                .opacity(engine.state != .playing ? 1 : 0)
                .allowsHitTesting(engine.state != .playing)

            progressSection
        }
        .padding(.horizontal)
    }

    private var wpmControls: some View {
        HStack(spacing: 20) {
            Button {
                engine.wpm -= 25
                persistedWPM = engine.wpm
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.walnut.opacity(0.8))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Decrease speed by 25 words per minute")

            Text("\(engine.wpm) WPM")
                .font(.numeric(size: 18, weight: .medium))
                .foregroundStyle(Color.agedGold)
                .frame(minWidth: 100)
                .accessibilityLabel("\(engine.wpm) words per minute")

            Button {
                engine.wpm += 25
                persistedWPM = engine.wpm
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.walnut.opacity(0.8))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Increase speed by 25 words per minute")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                engine.play()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.crimsonSoft)
            }
            .frame(minWidth: 44, minHeight: 44)

            Button {
                addBookmark()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.agedGold)
                    .padding(10)
                    .background(Color.walnut.opacity(0.6), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)

            Button {
                toggleHighlight()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                    Text(highlightStartIndex != nil ? "Stop" : "Highlight")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(highlightStartIndex != nil ? .white : Color.rsvpText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    highlightStartIndex != nil ? Color.crimson : Color.walnut.opacity(0.6),
                    in: Capsule()
                )
            }
            .frame(minHeight: 44)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.walnut)
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
            .foregroundStyle(Color.rsvpText.opacity(0.4))
            .monospacedDigit()
        }
    }

    // MARK: - Scrub Gesture

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard engine.state != .playing else { return }

                let now = Date.now
                let deltaX = -(value.translation.width - lastDragX)
                let deltaTime = now.timeIntervalSince(lastDragTime)

                if deltaTime > 0 {
                    dragVelocity = abs(deltaX / CGFloat(deltaTime))
                }

                let velocityFactor = min(dragVelocity / 500, maxVelocityMultiplier / basePtsPerWord)
                let effectivePtsPerWord = basePtsPerWord / max(1, velocityFactor)

                dragAccumulator += deltaX
                let wordDelta = Int(dragAccumulator / effectivePtsPerWord)

                if wordDelta != 0 {
                    let newIndex = engine.currentIndex + wordDelta
                    engine.seek(to: newIndex)
                    dragAccumulator -= CGFloat(wordDelta) * effectivePtsPerWord

                    if abs(wordDelta) >= hapticInterval || engine.currentIndex % hapticInterval == 0 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                lastDragX = value.translation.width
                lastDragTime = now
            }
            .onEnded { _ in
                lastDragX = 0
                dragAccumulator = 0
                dragVelocity = 0
            }
    }

    // MARK: - Actions

    private func addBookmark() {
        let preview = Bookmark.previewText(from: cachedWords, at: engine.currentIndex)
        let bookmark = Bookmark(wordIndex: engine.currentIndex, previewText: preview)
        bookmark.book = book
        modelContext.insert(bookmark)

        withAnimation(.easeOut(duration: 0.3)) { bookmarkFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.2)) { bookmarkFlash = false }
        }
    }

    private func toggleHighlight() {
        if let startIndex = highlightStartIndex {
            let endIndex = engine.currentIndex
            let actualStart = min(startIndex, endIndex)
            let actualEnd = max(startIndex, endIndex)
            let text = Highlight.captureText(from: cachedWords, start: actualStart, end: actualEnd)
            let highlight = Highlight(startWordIndex: actualStart, endWordIndex: actualEnd, highlightedText: text)
            highlight.book = book
            modelContext.insert(highlight)
            highlightStartIndex = nil

            withAnimation(.easeOut(duration: 0.3)) { highlightFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.2)) { highlightFlash = false }
            }
        } else {
            highlightStartIndex = engine.currentIndex
        }
    }
}
