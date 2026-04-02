import SwiftUI

struct NowReadingView: View {
    @EnvironmentObject var syncService: WatchSyncService

    @State private var showRSVP = false

    var body: some View {
        Group {
            if syncService.isReceiving, let title = syncService.receivingTitle {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.red)
                    Text("Receiving")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding()
                .transition(.opacity)
            } else if let title = syncService.lastReceivedBookTitle,
                      syncService.lastReceivedBookText != nil {
                VStack(spacing: 12) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Button {
                        showRSVP = true
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showRSVP) {
                    WatchRSVPView()
                        .environmentObject(syncService)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.right.inward")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Open SpeedRead on iPhone to add books!")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .animation(.easeInOut, value: syncService.isReceiving)
    }
}
