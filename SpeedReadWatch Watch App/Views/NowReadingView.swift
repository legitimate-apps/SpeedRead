import SwiftUI

struct NowReadingView: View {
    @EnvironmentObject var syncService: WatchSyncService

    @State private var showRSVP = false

    var body: some View {
        ZStack {
            Color.walnut.ignoresSafeArea()

            Group {
                if syncService.isReceiving, let title = syncService.receivingTitle {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.agedGold)
                        Text("Receiving")
                            .font(.displayFont(size: 16, weight: .semibold))
                            .foregroundStyle(Color.parchment)
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.parchment.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding()
                    .transition(.opacity)
                } else if let title = syncService.lastReceivedBookTitle,
                          syncService.lastReceivedBookText != nil {
                    VStack(spacing: 12) {
                        Text(title)
                            .font(.displayFont(size: 15, weight: .semibold))
                            .foregroundStyle(Color.parchment)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Button {
                            showRSVP = true
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.crimsonSoft)
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
                        Image(systemName: "books.vertical")
                            .font(.title2)
                            .foregroundStyle(Color.agedGold)
                        Text("Open your library on iPhone")
                            .font(.displayFont(size: 13, weight: .regular))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .padding()
                }
            }
        }
        .animation(.easeInOut, value: syncService.isReceiving)
    }
}
