//  HighlightListView.swift
import SwiftUI
import SwiftData

struct HighlightListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editingNote: Highlight?
    @State private var noteDraft = ""

    var body: some View {
        let displayedHighlights = AnnotationListLogic.ordered(book.highlights)

        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                if displayedHighlights.isEmpty {
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
                        ForEach(displayedHighlights) { highlight in
                            Button {
                                engine.seek(to: highlight.startWordIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(AnnotationListLogic.rangeLabel(
                                            startWordIndex: highlight.startWordIndex,
                                            endWordIndex: highlight.endWordIndex
                                        ))
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
                                    if let note = highlight.note {
                                        Label(note, systemImage: "note.text")
                                            .font(.system(size: 13).italic())
                                            .foregroundStyle(Color.agedGold.opacity(0.9))
                                            .lineLimit(4)
                                    }
                                    if let source = AnnotationListLogic.sourceLabel(highlight.syncSource) {
                                        Text(source)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.rsvpText.opacity(0.4))
                                    }
                                    Text(highlight.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.rsvpText.opacity(0.3))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.walnut.opacity(0.3))
                            .swipeActions(edge: .leading) {
                                if highlight.isEditableOnServer {
                                    Button {
                                        noteDraft = highlight.note ?? ""
                                        editingNote = highlight
                                    } label: {
                                        Label(highlight.note == nil ? "Add Note" : "Edit Note", systemImage: "note.text")
                                    }
                                    .tint(Color.agedGold)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for highlight in AnnotationListLogic.highlightsToDelete(
                                at: indexSet,
                                from: displayedHighlights
                            ) {
                                ServerAnnotationSync.shared.delete(highlight, in: modelContext)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .alert("Note", isPresented: Binding(
                get: { editingNote != nil },
                set: { if !$0 { editingNote = nil } }
            )) {
                TextField("Your note", text: $noteDraft, axis: .vertical)
                Button("Save") {
                    if let editingNote {
                        ServerAnnotationSync.shared.setNote(noteDraft, on: editingNote, in: modelContext)
                    }
                    editingNote = nil
                }
                Button("Cancel", role: .cancel) { editingNote = nil }
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
