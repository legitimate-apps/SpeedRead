import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss

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
            onTogglePlayback: { session.togglePlayback() },
            onClose: {
                sync(session.close(book: currentBook))
                dismiss()
            },
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
            session.seek(toCrownValue: newValue, wordCount: words.count)
        }
        .onAppear {
            crownValue = session.load(book: currentBook, wpm: persistedWPM)
        }
        .onDisappear {
            sync(session.handleDisappear(book: currentBook))
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(engine: engine)
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
}
