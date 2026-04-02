import SwiftUI

struct WatchRSVPView: View {
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false
    @State private var crownValue: Double = 0

    private var words: [String] {
        (syncService.lastReceivedBookText ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine.state == .playing {
                // Playing -- show word, tap to pause
                RSVPWordView(segments: engine.currentSegments, fontSize: 20)
                    .onTapGesture { engine.pause() }

                VStack {
                    HStack {
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    Spacer()
                }
            } else {
                // Paused
                VStack(spacing: 0) {
                    // Top bar: settings (left), back (right)
                    HStack {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            syncService.syncReadingPosition(
                                bookTitle: syncService.lastReceivedBookTitle ?? "",
                                wordIndex: engine.currentIndex
                            )
                            engine.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    Spacer()

                    // Current word preview
                    RSVPWordView(segments: engine.currentSegments, fontSize: 18)

                    Spacer()

                    // Play button
                    Button { engine.play() } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Text("\(engine.wpm) WPM")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .padding(.bottom, 4)
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
            let w = words
            engine.load(words: w, startingAt: syncService.lastReceivedPosition)
            crownValue = Double(syncService.lastReceivedPosition)
        }
        .onDisappear {
            syncService.syncReadingPosition(
                bookTitle: syncService.lastReceivedBookTitle ?? "",
                wordIndex: engine.currentIndex
            )
            engine.stop()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView(engine: engine)
        }
    }
}
