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
        ZStack {
            Color.rsvpBackground
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { session.togglePlayback() }
                .onLongPressGesture {
                    session.prepareForSettings()
                    showSettings = true
                }

            if engine.state == .playing {
                RSVPWordView(segments: engine.currentSegments, fontSize: 20)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            sync(session.close(book: currentBook))
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.walnut.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.walnut.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    Spacer()

                    RSVPWordView(segments: engine.currentSegments, fontSize: 18)
                        .allowsHitTesting(false)

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.crimsonSoft)
                        .allowsHitTesting(false)

                    Text("\(engine.wpm) WPM")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.agedGold)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
        }
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
