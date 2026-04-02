//  HighlightListView.swift
import SwiftUI
import SwiftData

struct HighlightListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sortedHighlights: [Highlight] {
        book.highlights.sorted { $0.startWordIndex < $1.startWordIndex }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                if sortedHighlights.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                        Text("No highlights yet")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.rsvpText.opacity(0.5))
                        Text("Tap Highlight while paused, read or scrub, then tap Stop")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(sortedHighlights) { highlight in
                            Button {
                                engine.seek(to: highlight.startWordIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Words \(highlight.startWordIndex + 1)–\(highlight.endWordIndex + 1)")
                                            .font(.numeric(size: 13, weight: .medium))
                                            .foregroundStyle(Color.agedGold)
                                        Spacer()
                                        Text("\(highlight.wordSpan) words")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                                    }
                                    Text(highlight.highlightedText)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.rsvpText.opacity(0.7))
                                        .lineLimit(3)
                                    Text(highlight.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.rsvpText.opacity(0.3))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.walnut.opacity(0.3))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(sortedHighlights[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
