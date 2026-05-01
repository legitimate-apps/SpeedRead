//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject var syncService: WatchSyncService
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var showThemePicker = false
    @State private var importError: String?
    @State private var showError = false
    @State private var didLoadSamples = false
    @State private var autoOpenedBook: Book?

    private let booksPerShelf = 4

    private var shelves: [[Book]] {
        stride(from: 0, to: books.count, by: booksPerShelf).map {
            Array(books[$0..<min($0 + booksPerShelf, books.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()

                if books.isEmpty {
                    emptyLibraryView
                } else {
                    bookshelfView
                }
            }
            .navigationTitle("Your Library")
            .toolbarBackground(themeManager.currentTheme.backgroundColor, for: .navigationBar)
            .task {
                guard !didLoadSamples else { return }
                didLoadSamples = true
                SampleBookLoader(modelContext: modelContext).loadSampleBooksIfNeeded()
                // Debug hook: --auto-send-first-book flag triggers a Watch send on
                // launch so the paired-sim wiring can be verified without driving
                // the context menu.
                if ProcessInfo.processInfo.arguments.contains("--auto-send-first-book"),
                   let book = books.first {
                    try? await Task.sleep(for: .seconds(1))
                    syncService.sendBook(
                        id: book.id, title: book.title, author: book.author,
                        text: book.extractedText, wordCount: book.wordCount
                    )
                }
                if ProcessInfo.processInfo.arguments.contains("--auto-open-first-book") {
                    try? await Task.sleep(for: .milliseconds(800))
                    autoOpenedBook = books.first(where: { $0.title.localizedCaseInsensitiveContains("Metamorphosis") })
                        ?? books.first
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showThemePicker = true
                        } label: {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(Color.crimsonSoft)
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.crimsonSoft)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub, .plainText, .rtf, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .navigationDestination(item: $autoOpenedBook) { book in
                ReaderView(book: book)
            }
            .overlay(alignment: .bottom) {
                if case .sending(let title) = syncService.sendState {
                    SendToast(icon: "arrow.up.circle", message: "Sending \(title)...", color: Color.agedGold)
                } else if case .sent(let title) = syncService.sendState {
                    SendToast(icon: "checkmark.circle.fill", message: "Sent \(title) to Watch", color: Color.agedGold)
                } else if case .failed(let error) = syncService.sendState {
                    SendToast(icon: "exclamationmark.triangle.fill", message: error, color: Color.crimsonSoft)
                }
            }
            .animation(.easeInOut, value: syncService.sendState != .idle)
            .sheet(isPresented: $showThemePicker) {
                ThemePickerView()
            }
        }
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            BookshelfRowView { }
            BookshelfRowView { }

            Text("Your shelves are waiting...")
                .font(.displayFont(size: 20, weight: .regular))
                .italic()
                .foregroundStyle(Color.walnutLight)
                .padding(.top, 20)

            Button {
                showImporter = true
            } label: {
                Label("Import a Book", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.parchment)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.crimsonSoft, in: Capsule())
            }
        }
        .padding()
    }

    private var bookshelfView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelfBooks in
                    BookshelfRowView {
                        ForEach(shelfBooks) { book in
                            NavigationLink(value: book) {
                                BookSpineView(
                                    title: book.title,
                                    author: book.author,
                                    progress: book.progress,
                                    wordCount: book.wordCount
                                )
                            }
                            .contextMenu {
                                Button {
                                    syncService.sendBook(id: book.id, title: book.title, author: book.author, text: book.extractedText, wordCount: book.wordCount)
                                } label: {
                                    Label("Send to Watch", systemImage: "applewatch")
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importer = DocumentImporter(modelContext: modelContext)
                _ = try importer.importFile(at: url)
            } catch {
                importError = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showError = true
        }
    }
}

private struct SendToast: View {
    let icon: String
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
