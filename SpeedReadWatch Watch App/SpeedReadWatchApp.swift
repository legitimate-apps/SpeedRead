import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            NowReadingView()
                .environmentObject(syncService)
                .onAppear { syncService.activate() }
        }
    }
}
