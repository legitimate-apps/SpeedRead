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
    @State private var importSession = LibraryImportSession()
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
            .toolbarColorScheme(themeManager.currentTheme.toolbarColorScheme, for: .navigationBar)
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
                        text: book.extractedText, wordCount: book.wordCount,
                        chapters: book.chapters
                    )
                }
                if ProcessInfo.processInfo.arguments.contains("--auto-open-first-book") {
                    try? await Task.sleep(for: .milliseconds(800))
                    autoOpenedBook = books.first(where: { $0.title.localizedCaseInsensitiveContains("Metamorphosis") })
                        ?? books.first
                }
                #if DEBUG
                if let fixture = ChapterUITestFixture.book() {
                    modelContext.insert(fixture)
                    autoOpenedBook = fixture
                }
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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--auto-open-theme-picker") {
                    try? await Task.sleep(for: .milliseconds(700))
                    showThemePicker = true
                }
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showThemePicker = true
                        } label: {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(themeManager.currentTheme.chromeAccent)
                        }

                        Button {
                            showBrowse = true
                        } label: {
                            Image(systemName: "icloud.and.arrow.down")
                                .foregroundStyle(themeManager.currentTheme.chromeAccent)
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(themeManager.currentTheme.chromeAccent)
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(themeManager.currentTheme.chromeAccent)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub, .plainText, .rtf, .text],
                allowsMultipleSelection: false
            ) { result in
                importSession.handleImport(result, modelContext: modelContext)
            }
            .alert("Import Error", isPresented: $importSession.showError) {
                Button("OK") {}
            } message: {
                Text(importSession.importError ?? "Unknown error")
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .navigationDestination(item: $autoOpenedBook) { book in
                ReaderView(book: book)
            }
            .overlay(alignment: .bottom) {
                if case .sending(let title) = syncService.sendState {
                    SendToast(icon: "arrow.up.circle", message: "Sending \(title)...", color: Color.appGoldText)
                } else if case .sent(let title) = syncService.sendState {
                    SendToast(icon: "checkmark.circle.fill", message: "Sent \(title) to Watch", color: Color.appSuccess)
                } else if case .failed(let error) = syncService.sendState {
                    SendToast(icon: "exclamationmark.triangle.fill", message: error, color: Color.appError)
                }
            }
            .overlay(alignment: .top) {
                if let offer = syncService.pendingWatchPositionOffer {
                    WatchPositionOfferBanner(
                        offer: offer,
                        onContinue: { syncService.continueFromWatch(offer) },
                        onDismiss: { syncService.dismissWatchPositionOffer() }
                    )
                }
            }
            .animation(.easeInOut, value: syncService.sendState != .idle)
            .animation(.easeInOut, value: syncService.pendingWatchPositionOffer)
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
                .foregroundStyle(themeManager.currentTheme.chromeText)
                .padding(.top, 20)

            Button {
                showImporter = true
            } label: {
                Label("Import a Book", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(themeManager.currentTheme.chromeOnAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.chromeAccent, in: Capsule())
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
                                            syncService.sendBook(
                                                id: book.id,
                                                title: book.title,
                                                author: book.author,
                                                text: book.extractedText,
                                                wordCount: book.wordCount,
                                                chapters: book.chapters
                                            )
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

}

/// Owns the file importer result and the alert state presented by the library.
@MainActor
@Observable
final class LibraryImportSession {
    var importError: String?
    var showError = false

    func handleImport(_ result: Result<[URL], Error>, modelContext: ModelContext) {
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

struct WatchPositionOfferBanner: View {
    let offer: WatchSyncService.PositionOffer
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(offer.displayText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appInk)

            HStack(spacing: 12) {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .accessibilityIdentifier("watch-position-offer-continue")

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(Color.appAccent)
                    .accessibilityIdentifier("watch-position-offer-dismiss")
            }
        }
        .padding(14)
        // Opaque card: the old translucent material let the parchment shelf show through,
        // leaving cream text on a cream card.
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appInk.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("watch-position-offer")
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
                .foregroundStyle(Color.appInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
