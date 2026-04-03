import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                NowReadingView()
                    .containerBackground(Color.walnut.gradient, for: .tabView)

                WatchLibraryView()
                    .containerBackground(Color.inkBlack.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(syncService)
            .onAppear { syncService.activate() }
        }
    }
}
