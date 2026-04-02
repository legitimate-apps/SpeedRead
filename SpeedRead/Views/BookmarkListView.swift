//  BookmarkListView.swift
import SwiftUI
import SwiftData

struct BookmarkListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var sortedBookmarks: [Bookmark] {
        book.bookmarks.sorted { $0.wordIndex < $1.wordIndex }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                if sortedBookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                        Text("No bookmarks yet")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.rsvpText.opacity(0.5))
                        Text("Tap the bookmark icon while paused to save your place")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rsvpText.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(sortedBookmarks) { bookmark in
                            Button {
                                engine.seek(to: bookmark.wordIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Word \(bookmark.wordIndex + 1)")
                                        .font(.numeric(size: 13, weight: .medium))
                                        .foregroundStyle(Color.agedGold)
                                    Text(bookmark.previewText)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.rsvpText.opacity(0.7))
                                        .lineLimit(2)
                                    Text(bookmark.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.rsvpText.opacity(0.3))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.walnut.opacity(0.3))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(sortedBookmarks[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Bookmarks")
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
