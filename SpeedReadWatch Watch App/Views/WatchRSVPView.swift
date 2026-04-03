import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false
    @State private var crownValue: Double = 0

    private var currentBook: WatchBook? { syncService.currentBook }

    private var words: [String] {
        currentBook?.words ?? []
    }

    var body: some View {
        ZStack {
            Color.rsvpBackground.ignoresSafeArea()

            if engine.state == .playing {
                RSVPWordView(segments: engine.currentSegments, fontSize: 20)
                    .onTapGesture { engine.pause() }
                    .onLongPressGesture {
                        engine.pause()
                        showSettings = true
                    }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            if let book = currentBook {
                                syncService.syncReadingPosition(
                                    bookId: book.id,
                                    bookTitle: book.title,
                                    wordIndex: engine.currentIndex
                                )
                            }
                            engine.stop()
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

                    Spacer()

                    Button { engine.play() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.crimsonSoft)
                    }
                    .buttonStyle(.plain)

                    Text("\(engine.wpm) WPM")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.agedGold)
                        .padding(.bottom, 4)
                }
                .onLongPressGesture {
                    showSettings = true
                }
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: max(1, Double(words.count - 1)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            if engine.state != .playing {
                engine.seek(to: Int(newValue))
            }
        }
        .onAppear {
            guard let book = currentBook else { return }
            engine.load(words: book.words, startingAt: book.lastReadIndex)
            crownValue = Double(book.lastReadIndex)
        }
        .onDisappear {
            if let book = currentBook {
                syncService.syncReadingPosition(
                    bookId: book.id,
                    bookTitle: book.title,
                    wordIndex: engine.currentIndex
                )
            }
            engine.stop()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(engine: engine)
        }
    }
}
