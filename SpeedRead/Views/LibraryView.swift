//  LibraryView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var syncService: WatchSyncService
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showImporter = false
    @State private var showThemePicker = false
    @State private var showBrowse = false
    @State private var showSettings = false
    @State private var importError: String?
    @State private var showError = false
    @State private var didLoadSamples = false
    @State private var autoOpenedBook: Book?

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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--seed-test-opds-server") {
                    seedTestOPDSServer()
                }
                #endif
                if ProcessInfo.processInfo.arguments.contains("--auto-open-settings") {
                    try? await Task.sleep(for: .milliseconds(700))
                    showSettings = true
                }
                if ProcessInfo.processInfo.arguments.contains("--auto-open-browse") {
                    try? await Task.sleep(for: .milliseconds(700))
                    showBrowse = true
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
                            showBrowse = true
                        } label: {
                            Image(systemName: "icloud.and.arrow.down")
                                .foregroundStyle(Color.crimsonSoft)
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.crimsonSoft)
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
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
            .sheet(isPresented: $showBrowse) {
                BrowseServerView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
        GeometryReader { geometry in
            let metrics = LibraryLayoutMetrics(
                isRegularWidth: horizontalSizeClass == .regular,
                containerWidth: geometry.size.width
            )
            let modelShelves = metrics.shelves(for: books)
            let visibleShelfCount = max(
                modelShelves.count,
                metrics.minimumVisibleShelfCount(viewportHeight: geometry.size.height)
            )

            ScrollView {
                LazyVStack(spacing: metrics.shelfSpacing) {
                    ForEach(0..<visibleShelfCount, id: \.self) { shelfIndex in
                        BookshelfRowView {
                            if shelfIndex < modelShelves.count {
                                ForEach(modelShelves[shelfIndex]) { book in
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
                }
                .padding(.top, 16)
            }
        }
    }

    #if DEBUG
    /// Debug-only: seed an OPDS server so scripted verification can capture the
    /// Browse / Detail screens without driving the Settings form by hand.
    ///
    /// The server address and credentials are read from the environment and are
    /// deliberately absent from the repository and from any shipping binary.
    /// Supply them at launch:
    ///
    ///     SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_URL=https://example/opds/ \
    ///     SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_USER=someuser \
    ///     SIMCTL_CHILD_SPEEDREAD_TEST_OPDS_PASSWORD=secret \
    ///     xcrun simctl launch <udid> com.legitimateapps.SpeedRead --seed-test-opds-server
    ///
    /// No-op if any variable is unset, or if that server is already configured.
    private func seedTestOPDSServer() {
        let env = ProcessInfo.processInfo.environment
        guard let urlString = env["SPEEDREAD_TEST_OPDS_URL"],
              let url = URL(string: urlString),
              let username = env["SPEEDREAD_TEST_OPDS_USER"],
              let password = env["SPEEDREAD_TEST_OPDS_PASSWORD"]
        else { return }

        let descriptor = FetchDescriptor<OPDSServer>()
        if let existing = (try? modelContext.fetch(descriptor)) ?? nil,
           existing.contains(where: { $0.baseURLString == url.absoluteString }) {
            return
        }
        let server = OPDSServer(
            name: env["SPEEDREAD_TEST_OPDS_NAME"] ?? "Home library",
            baseURL: url,
            username: username,
            allowInsecureHTTP: url.scheme == "http",
            sortIndex: Int(Date().timeIntervalSince1970)
        )
        modelContext.insert(server)
        try? KeychainStore.setPassword(password, for: server.keychainTag)
        try? modelContext.save()
    }
    #endif

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
