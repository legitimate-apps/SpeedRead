//  WatchLibraryView.swift
import SwiftUI

struct WatchLibraryView: View {
    @EnvironmentObject var syncService: WatchSyncService

    var body: some View {
        NavigationStack {
            Group {
                if syncService.library.books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("Library")
            .containerBackground(Color.inkBlack.gradient, for: .navigation)
            .navigationDestination(for: WatchBook.self) { book in
                WatchBookDetailView(book: book)
            }
        }
    }

    private var bookList: some View {
        List {
            ForEach(syncService.library.sortedBooks) { book in
                NavigationLink(value: book) {
                    bookRow(book)
                }
                .listRowBackground(Color.walnut.opacity(0.3))
            }
            .onDelete(perform: deleteBooks)
        }
    }

    private func bookRow(_ book: WatchBook) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(SpineColor.color(for: book.title))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.parchment)
                    .lineLimit(2)

                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(Color.parchment.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if book.id == syncService.library.currentBookId {
                Circle()
                    .fill(Color.crimsonSoft)
                    .frame(width: 8, height: 8)
            } else if book.progress > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.parchment.opacity(0.15), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: book.progress)
                        .stroke(Color.agedGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(Color.agedGold)
            Text("Send books from your iPhone library")
                .font(.displayFont(size: 13, weight: .regular))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.parchment.opacity(0.6))
        }
        .padding()
    }

    private func deleteBooks(at offsets: IndexSet) {
        let sorted = syncService.library.sortedBooks
        for index in offsets {
            syncService.library.removeBook(id: sorted[index].id)
        }
        syncService.persistLibrary()
    }
}
