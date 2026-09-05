import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService

    @State private var session = WatchRSVPSession()
    @State private var showSettings = false
    @State private var crownValue: Double = 0
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = 300

    private var currentBook: WatchBook? { syncService.currentBook }
    private var engine: RSVPEngine { session.engine }

    private var words: [String] {
        currentBook?.words ?? []
    }

    var body: some View {
        WatchRSVPSurface(
            engine: engine,
            onTogglePlayback: { sync(session.togglePlayback(book: currentBook)) },
            onOpenSettings: {
                session.prepareForSettings()
                showSettings = true
            }
        )
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
        .onChange(of: crownValue) { _, newValue in
            let normalized = session.seek(toCrownValue: newValue, wordCount: words.count)
            if normalized != newValue {
                crownValue = normalized
            }
            persistBrowsePosition()
        }
        .onChange(of: engine.currentIndex) { _, _ in
            let normalized = session.synchronizeCrownValue(wordCount: words.count)
            if crownValue != normalized {
                crownValue = normalized
            }
            if engine.state == .playing {
                sync(session.commitPlaybackAdvanceIfNeeded(book: currentBook))
            }
        }
        .onAppear {
            crownValue = session.load(book: currentBook, wpm: persistedWPM)
        }
        .onDisappear {
            sync(session.handleDisappear(book: currentBook))
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(
                engine: engine,
                chapters: currentBook?.chapters ?? [],
                currentWordIndex: engine.currentIndex,
                onSelectChapter: { chapter in
                    guard let currentBook else { return }
                    crownValue = WatchChapterSelection.browse(
                        to: chapter,
                        in: currentBook,
                        session: session,
                        library: &syncService.library
                    )
                    syncService.persistLibrary()
                    showSettings = false
                },
                onRestoreReadingPosition: {
                    guard let currentBook else { return }
                    crownValue = session.restoreReadingPosition(book: currentBook)
                    persistBrowsePosition()
                }
            )
        }
    }

    private func sync(_ commit: WatchRSVPPositionCommit?) {
        guard let commit else { return }
        syncService.syncReadingPosition(
            bookId: commit.bookId,
            bookTitle: commit.bookTitle,
            wordIndex: commit.wordIndex
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
    }
}
