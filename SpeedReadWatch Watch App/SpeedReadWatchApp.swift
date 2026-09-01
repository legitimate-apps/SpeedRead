import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    private let launchesCrownDirectionFixture: Bool

    init() {
        #if DEBUG
        launchesCrownDirectionFixture = WatchAppLaunchLogic.destination() == .crownDirectionFixture
        if launchesCrownDirectionFixture {
            let book = WatchAppLaunchLogic.crownDirectionFixture()
            syncService.library = WatchLibrary(books: [book], currentBookId: book.id)
        }
        #else
        launchesCrownDirectionFixture = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if launchesCrownDirectionFixture {
                WatchRSVPView()
                    .environmentObject(syncService)
            } else {
                WatchLibraryView()
                    .environmentObject(syncService)
                    .onAppear { syncService.activate() }
            }
        }
    }
}
