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

struct ReaderHighlightPicker: View {
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
