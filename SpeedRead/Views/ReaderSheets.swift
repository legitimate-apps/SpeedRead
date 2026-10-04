import SwiftUI

struct ReaderSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var themeMode: String
    var palette: ReaderPalette = ReaderThemeMode.parchment.palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    HStack(spacing: 12) {
                        ForEach(ReaderThemeMode.allCases, id: \.rawValue) { mode in
                            themeSwatch(mode)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Typography") {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .foregroundStyle(palette.bodyText.opacity(0.65))
                            .monospacedDigit()
                    }
                    Slider(
                        value: $fontSize,
                        in: ReaderConfig.Classic.fontSizeRange,
                        step: 1
                    )
                    .tint(palette.accent)

                    HStack {
                        Text("Line spacing")
                        Spacer()
                        Text("\(Int(lineSpacing)) pt")
                            .foregroundStyle(palette.bodyText.opacity(0.65))
                            .monospacedDigit()
                    }
                    Slider(
                        value: $lineSpacing,
                        in: ReaderConfig.Classic.lineSpacingRange,
                        step: ReaderConfig.Classic.lineSpacingStep
                    )
                    .tint(palette.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(palette.rowFill)
            .foregroundStyle(palette.bodyText)
            .background(palette.background)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarColorScheme(palette.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reader Settings")
                        .font(.displayFont(size: 17, weight: .semibold))
                        .foregroundStyle(palette.titleText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func themeSwatch(_ mode: ReaderThemeMode) -> some View {
        let isSelected = themeMode == mode.rawValue
        let swatchPalette = mode.palette

        return Button {
            themeMode = mode.rawValue
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                Text("Aa")
                    .font(.displayFont(size: 22, weight: .medium))
                    .foregroundStyle(swatchPalette.titleText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(swatchPalette.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Color.agedGold : swatchPalette.bodyText.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                Text(mode.rawValue.capitalized)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(palette.bodyText.opacity(isSelected ? 0.9 : 0.6))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.rawValue.capitalized)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ReaderBookmarkPicker: View {
    let book: Book
    var palette: ReaderPalette = ReaderThemeMode.parchment.palette
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    func select(_ bookmark: Bookmark) {
        onSelect(bookmark.wordIndex)
    }

    func orderedBookmarks() -> [Bookmark] {
        AnnotationListLogic.ordered(book.bookmarks)
    }

    func rowLabel(for bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bookmark.previewText)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(palette.bodyText)
                .lineLimit(2)
            Text(AnnotationListLogic.positionLabel(wordIndex: bookmark.wordIndex))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.bodyText.opacity(0.6))
        }
    }

    var body: some View {
        let displayedBookmarks = orderedBookmarks()

        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if displayedBookmarks.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No bookmarks yet",
                        message: "Tap the bookmark icon in RSVP while paused to save your place",
                        tint: palette.bodyText.opacity(0.45),
                        titleColor: palette.titleText.opacity(0.75),
                        messageColor: palette.bodyText.opacity(0.55),
                        titleFont: .system(size: 16, weight: .medium, design: .serif),
                        messageFont: .system(size: 13, design: .serif)
                    )
                } else {
                    List {
                        ForEach(displayedBookmarks, id: \.id) { bookmark in
                            Button {
                                select(bookmark)
                                dismiss()
                            } label: {
                                rowLabel(for: bookmark)
                            }
                            .listRowBackground(palette.rowFill)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarColorScheme(palette.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Bookmarks")
                        .font(.displayFont(size: 17, weight: .semibold))
                        .foregroundStyle(palette.titleText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

struct ReaderHighlightPicker: View {
    let book: Book
    var palette: ReaderPalette = ReaderThemeMode.parchment.palette
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    func select(_ highlight: Highlight) {
        onSelect(highlight.startWordIndex)
    }

    func orderedHighlights() -> [Highlight] {
        AnnotationListLogic.ordered(book.highlights)
    }

    func rowLabel(for highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlight.highlightedText)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(palette.bodyText)
                .lineLimit(3)
            if let note = highlight.note {
                Label(note, systemImage: "note.text")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(palette.bodyText.opacity(0.7))
                    .lineLimit(4)
            }
            Text(AnnotationListLogic.rangeLabel(
                startWordIndex: highlight.startWordIndex,
                endWordIndex: highlight.endWordIndex
            ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.bodyText.opacity(0.6))
        }
    }

    var body: some View {
        let displayedHighlights = orderedHighlights()

        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if displayedHighlights.isEmpty {
                    EmptyStateView(
                        icon: "highlighter",
                        title: "No highlights yet",
                        message: "Tap Highlight in RSVP while paused, read or scrub, then tap Stop",
                        tint: palette.bodyText.opacity(0.45),
                        titleColor: palette.titleText.opacity(0.75),
                        messageColor: palette.bodyText.opacity(0.55),
                        titleFont: .system(size: 16, weight: .medium, design: .serif),
                        messageFont: .system(size: 13, design: .serif)
                    )
                } else {
                    List {
                        ForEach(displayedHighlights, id: \.id) { highlight in
                            Button {
                                select(highlight)
                                dismiss()
                            } label: {
                                rowLabel(for: highlight)
                            }
                            .listRowBackground(palette.rowFill)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarColorScheme(palette.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Highlights")
                        .font(.displayFont(size: 17, weight: .semibold))
                        .foregroundStyle(palette.titleText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

struct ReaderChapterPicker: View {
    let chapters: ChapterNavigation
    let wordIndex: Int
    var palette: ReaderPalette = ReaderThemeMode.parchment.palette
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(chapters.rows.indices, id: \.self) { row in
                    let chapter = chapters.rows[row]
                    let isCurrent = chapters.isCurrent(row: row, at: wordIndex)
                    Button {
                        onSelect(chapter.startWordIndex)
                        dismiss()
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .font(.system(size: 15, weight: isCurrent ? .semibold : .regular, design: .serif))
                                .foregroundStyle(palette.bodyText)
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chapter.title)
                    .accessibilityValue(isCurrent ? "Current chapter" : "")
                    .accessibilityHint("Browse to chapter without changing your reading position")
                    .listRowBackground(palette.rowFill)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarColorScheme(palette.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Chapters")
                        .font(.displayFont(size: 17, weight: .semibold))
                        .foregroundStyle(palette.titleText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Close chapters")
                }
            }
        }
    }
}
