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

    private var currentBook: WatchBook? { syncService.currentBook }
    private var engine: RSVPEngine { session.engine }

    private var words: [String] {
        currentBook?.words ?? []
    }

    var surface: some View {
        WatchRSVPSurface(
            engine: engine,
            onTogglePlayback: togglePlayback,
            onOpenSettings: openSettings
        )
    }

    var body: some View {
        surface
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: CrownSeek.crownUpperBound(wordCount: words.count),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in seek(newValue) }
        .onChange(of: engine.currentIndex) { _, _ in synchronizePosition() }
        .onChange(of: engine.didFinish) { _, finished in
            if finished { synchronizePosition() }
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

    func togglePlayback() { sync(session.togglePlayback(book: currentBook)) }

    func openSettings() {
        session.prepareForSettings()
        showSettings = true
    }

    func load() { crownValue = session.load(book: currentBook, wpm: wpm) }

    func disappear() { sync(session.handleDisappear(book: currentBook)) }

    func seek(_ newValue: Double) {
        let normalized = session.seek(toCrownValue: newValue, wordCount: words.count)
        if normalized != newValue { crownValue = normalized }
        persistBrowsePosition()
    }

    func synchronizePosition() {
        let normalized = session.synchronizeCrownValue(wordCount: words.count)
        if crownValue != normalized { crownValue = normalized }
        if engine.state == .playing || engine.didFinish {
            sync(session.commitPlaybackAdvanceIfNeeded(book: currentBook))
        }
    }

    func selectChapter(_ chapter: ChapterMark) {
        guard let currentBook else { return }
        crownValue = WatchChapterSelection.browse(to: chapter, in: currentBook,
                                                  session: session, library: &syncService.library)
        syncService.persistLibrary()
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
            wordIndex: commit.wordIndex
        )
        if commit.didFinish, syncService.library.markFinishedLocally(bookId: commit.bookId) {
            syncService.persistLibrary()
        }
    }

    private func persistBrowsePosition() {
        guard WatchRSVPViewLogic.recordBrowsePosition(
            book: currentBook,
            index: engine.currentIndex,
            engineState: engine.state,
            in: &syncService.library
        ) else { return }
        syncService.persistLibrary()
    }
}
