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
                // Playing -- tap to pause, long press for settings
                RSVPWordView(segments: engine.currentSegments, fontSize: 20)
                    .onTapGesture { engine.pause() }
                    .onLongPressGesture {
                        engine.pause()
                        showSettings = true
                    }
            } else {
                // Paused
                VStack(spacing: 0) {
                    // Top bar: back (left), settings (right)
                    HStack {
                        Button {
                            syncService.syncReadingPosition(
                                bookTitle: syncService.lastReceivedBookTitle ?? "",
                                wordIndex: engine.currentIndex
                            )
                            engine.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.15), in: Circle())
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
