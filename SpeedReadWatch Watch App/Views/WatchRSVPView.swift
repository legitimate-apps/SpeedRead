import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService

    @State private var session = WatchRSVPSession()
    @State private var showSettings = false
    @State private var crownValue: Double = 0
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = 300

    var body: some View {
        WatchRSVPContent(syncService: syncService, session: session,
                         showSettings: $showSettings, crownValue: $crownValue, wpm: persistedWPM)
    }
}

struct WatchRSVPContent: View {
    @ObservedObject var syncService: WatchSyncService
    let session: WatchRSVPSession
    @Binding var showSettings: Bool
    @Binding var crownValue: Double
    let wpm: Int
    @Environment(\.scenePhase) private var scenePhase

    private var currentBook: WatchBook? { syncService.currentBook }
    private var engine: RSVPEngine { session.engine }
    private var readingElsewhere: RemotePresence? { syncService.remotePresence(for: currentBook?.id) }

    var surface: some View {
        WatchRSVPSurface(
            engine: engine,
            onTogglePlayback: togglePlayback,
            onOpenSettings: openSettings
        )
    }

    var body: some View {
        ZStack {
            // Under the card, VoiceOver must not reach the word or a Play that would bypass it.
            surface.accessibilityHidden(readingElsewhere != nil)
            if let presence = readingElsewhere, let book = currentBook {
                WatchReadingElsewhereCard(presence: presence, book: book, onReadHere: togglePlayback)
            }
        }
        .animation(.easeInOut, value: readingElsewhere)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: CrownSeek.crownUpperBound(wordCount: session.wordCount),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in seek(newValue) }
        .onChange(of: engine.currentIndex) { _, _ in synchronizePosition() }
        .onChange(of: engine.state) { _, _ in publishCrownValue() }
        .onChange(of: engine.didFinish) { _, finished in
            if finished {
                if let currentBook { syncService.endLocalRun(bookId: currentBook.id) }
                synchronizePosition()
            }
        }
        // The phone moved the place, or is reading: show its word.
        .onChange(of: currentBook?.browseWordIndex) { _, index in
            guard let index, let normalized = session.follow(placeAt: index) else { return }
            crownValue = normalized
        }
        .onChange(of: scenePhase) { _, phase in
            // A lowered wrist cannot read RSVP: pause, which hands the book back to the phone.
            if phase != .active, engine.state == .playing { togglePlayback() }
        }
        .onAppear(perform: load)
        .onDisappear(perform: disappear)
        .sheet(isPresented: $showSettings) { settings }
    }

    var settings: WatchSettingsView {
        WatchSettingsView(engine: engine, chapters: currentBook?.chapters ?? [],
                          currentWordIndex: engine.currentIndex,
                          onSelectChapter: selectChapter,
                          onRestoreReadingPosition: restoreReadingPosition)
    }

    func togglePlayback() {
        guard let book = currentBook else { return }
        if engine.state == .playing { syncService.endLocalRun(bookId: book.id) }
        let commit = session.togglePlayback(book: book)
        if engine.state == .playing {
            // Reading here takes the book over: the phone yields when it hears the heartbeat.
            syncService.beginLocalRun(
                bookId: book.id,
                snapshot: { [weak syncService, weak session] in
                    let bookId = book.id
                    guard let session,
                          let stored = syncService?.library.books.first(where: { $0.id == bookId }) else { return nil }
                    return stored.positionPayload().movingPlace(to: session.engine.currentIndex, at: Date())
                },
                onYield: { [weak session] presence in
                    guard let session else { return }
                    crownValue = session.yield(to: presence)
                }
            )
        }
        sync(commit)
    }

    func openSettings() {
        // A pause like any other: it commits and hands the book back, or the phone would stay
        // locked behind "Reading on Apple Watch" while the sheet is up.
        if engine.state == .playing { togglePlayback() }
        showSettings = true
    }

    func load() { crownValue = session.load(book: currentBook, wpm: wpm) }

    func disappear() {
        if let currentBook { syncService.endLocalRun(bookId: currentBook.id) }
        sync(session.handleDisappear(book: currentBook))
    }

    func seek(_ newValue: Double) {
        guard readingElsewhere == nil else {
            // The crown is inert while the phone reads; keep the binding on the visible word.
            crownValue = session.synchronizeCrownValue()
            return
        }
        let normalized = session.seek(toCrownValue: newValue)
        if normalized != newValue { crownValue = normalized }
        persistBrowsePosition()
    }

    func synchronizePosition() {
        publishCrownValue()
        if engine.state == .playing || engine.didFinish {
            sync(session.commitPlaybackAdvanceIfNeeded(book: currentBook))
        }
    }

    func publishCrownValue() {
        if let normalized = session.crownValueToPublish(), crownValue != normalized {
            crownValue = normalized
        }
    }

    func selectChapter(_ chapter: ChapterMark) {
        guard let currentBook else { return }
        crownValue = WatchChapterSelection.browse(to: chapter, in: currentBook,
                                                  session: session, library: &syncService.library)
        syncService.persistLibrary()
        publishPlace()
        showSettings = false
    }

    func restoreReadingPosition() {
        guard let currentBook else { return }
        crownValue = session.restoreReadingPosition(book: currentBook)
        persistBrowsePosition()
    }

    private func sync(_ commit: WatchRSVPPositionCommit?) {
        guard let commit else { return }
        syncService.syncReadingPosition(
            bookId: commit.bookId,
            bookTitle: commit.bookTitle,
            wordIndex: commit.wordIndex,
            didFinish: commit.didFinish
        )
    }

    private func persistBrowsePosition() {
        guard WatchRSVPViewLogic.recordBrowsePosition(
            book: currentBook,
            index: engine.currentIndex,
            engineState: engine.state,
            in: &syncService.library
        ) else { return }
        syncService.persistLibrary()
        publishPlace()
    }

    /// Every move is the place on the phone too.
    private func publishPlace() {
        guard let currentBook else { return }
        syncService.publishPlace(currentBook.positionPayload())
    }
}
