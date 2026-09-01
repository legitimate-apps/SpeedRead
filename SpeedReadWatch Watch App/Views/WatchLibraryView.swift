//  WatchLibraryView.swift
import SwiftUI

struct WatchLibraryView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @State private var showRSVP = false

    var body: some View {
        NavigationStack {
            WatchLibraryContent(syncService: syncService, showRSVP: $showRSVP)
            .navigationTitle("Library")
            .containerBackground(Color.inkBlack.gradient, for: .navigation)
            .navigationDestination(for: WatchBook.self) { book in
                WatchBookDetailView(book: book)
            }
        }
    }
}

struct WatchLibraryContent: View {
    @ObservedObject var syncService: WatchSyncService
    @Binding var showRSVP: Bool

    private var currentBook: WatchBook? { syncService.currentBook }

    var body: some View {
        Group {
            switch WatchLibraryLogic.state(
                isReceiving: syncService.isReceiving,
                library: syncService.library
            ) {
            case .receiving:
                receivingState
            case .empty:
                emptyState
            case .books:
                bookList
            }
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        List {
            // Now Reading section
            if let book = currentBook {
                Section {
                    Button {
                        showRSVP = true
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(WatchSpineColorLogic.color(for: book.title))
                                .frame(width: 4, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title)
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                    .foregroundStyle(Color.parchment)
                                    .lineLimit(2)

                                if let progressText = WatchLibraryPresentation.progressText(for: book) {
                                    Text(progressText)
                                        .font(.caption2)
                                        .foregroundStyle(Color.agedGold)
                                }
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.crimsonSoft)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.walnut.opacity(0.5))
                } header: {
                    Text("Now Reading")
                        .foregroundStyle(Color.agedGold)
                }
                .sheet(isPresented: $showRSVP) {
                    WatchRSVPView()
                        .environmentObject(syncService)
                }
            }

            // All books section
            Section {
                ForEach(syncService.library.sortedBooks) { book in
                    NavigationLink(value: book) {
                        bookRow(book)
                    }
                    .listRowBackground(Color.walnut.opacity(0.3))
                }
                .onDelete(perform: deleteBooks)
            } header: {
                if WatchLibraryPresentation.showsAllBooksHeader(currentBook: currentBook) {
                    Text("All Books")
                        .foregroundStyle(Color.parchment.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Book Row

    private func bookRow(_ book: WatchBook) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(WatchSpineColorLogic.color(for: book.title))
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

            switch WatchLibraryPresentation.accessory(
                for: book,
                currentBookID: syncService.library.currentBookId
            ) {
            case .current:
                Circle()
                    .fill(Color.crimsonSoft)
                    .frame(width: 8, height: 8)
            case .progress(let progress):
                ZStack {
                    Circle()
                        .stroke(Color.parchment.opacity(0.15), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.agedGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - States

    private var receivingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.agedGold)
            Text("Receiving")
                .font(.displayFont(size: 16, weight: .semibold))
                .foregroundStyle(Color.parchment)
            if let title = syncService.receivingTitle {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.parchment.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding()
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

    // MARK: - Actions

    private func deleteBooks(at offsets: IndexSet) {
        WatchLibraryLogic.removeBooks(at: offsets, from: &syncService.library)
        syncService.persistLibrary()
    }
}
