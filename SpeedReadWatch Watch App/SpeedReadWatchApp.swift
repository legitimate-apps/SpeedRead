import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared

    var body: some Scene {
        WindowGroup {
            WatchLibraryView()
                .environmentObject(syncService)
                .onAppear { syncService.activate() }
        }
    }
}
