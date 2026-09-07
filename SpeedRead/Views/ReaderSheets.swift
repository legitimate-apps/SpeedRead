import SwiftUI

struct ReaderSettingsSheet: View {
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
                    Slider(
                        value: $fontSize,
                        in: ReaderConfig.Classic.fontSizeRange,
                        step: 1
                    )

                    HStack {
                        Text("Line spacing")
                        Spacer()
                        Text("\(Int(lineSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $lineSpacing,
                        in: ReaderConfig.Classic.lineSpacingRange,
                        step: ReaderConfig.Classic.lineSpacingStep
                    )
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

struct ReaderBookmarkPicker: View {
    let book: Book
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
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(AnnotationListLogic.positionLabel(wordIndex: bookmark.wordIndex))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        let displayedBookmarks = orderedBookmarks()

        NavigationStack {
            List {
                if displayedBookmarks.isEmpty {
                    Text("No bookmarks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedBookmarks, id: \.id) { bookmark in
                        Button {
                            select(bookmark)
                            dismiss()
                        } label: {
                            rowLabel(for: bookmark)
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

struct ReaderHighlightPicker: View {
    let book: Book
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
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text(AnnotationListLogic.rangeLabel(
                startWordIndex: highlight.startWordIndex,
                endWordIndex: highlight.endWordIndex
            ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        let displayedHighlights = orderedHighlights()

        NavigationStack {
            List {
                if displayedHighlights.isEmpty {
                    Text("No highlights yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedHighlights, id: \.id) { highlight in
                        Button {
                            select(highlight)
                            dismiss()
                        } label: {
                            rowLabel(for: highlight)
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

struct ReaderChapterPicker: View {
    let chapters: ChapterNavigation
    let wordIndex: Int
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
                                .font(.system(size: 15, design: .serif))
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chapter.title)
                    .accessibilityValue(isCurrent ? "Current chapter" : "")
                    .accessibilityHint("Browse to chapter without changing your reading position")
                }
            }
            .navigationTitle("Chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close chapters")
                }
            }
        }
    }
}
