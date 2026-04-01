//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyLibraryView
                } else {
                    bookListView
                }
            }
            .navigationTitle("SpeedRead")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "Unknown error")
            }
        }
    }

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No Books", systemImage: "book.closed")
        } description: {
            Text("Import a PDF or EPUB to start speed reading.")
        } actions: {
            Button("Import Book") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var bookListView: some View {
        List {
            ForEach(books) { book in
                NavigationLink(value: book) {
                    BookRowView(book: book)
                }
            }
            .onDelete(perform: deleteBooks)
        }
        .navigationDestination(for: Book.self) { book in
            ReaderView(book: book)
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

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(books[index])
        }
    }
}

struct BookRowView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
            Text(book.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: book.progress)
                .tint(.red)
        }
        .padding(.vertical, 4)
    }
}
