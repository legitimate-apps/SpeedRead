import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService: WatchSyncService
    private let launchesCrownDirectionFixture: Bool

    init() {
        let service = WatchSyncService.shared
        _syncService = StateObject(wrappedValue: service)
        #if DEBUG
        launchesCrownDirectionFixture = Self.prepareLaunch(
            destination: WatchAppLaunchLogic.destination(), syncService: service)
        #else
        launchesCrownDirectionFixture = false
        #endif
    }

    #if DEBUG
    /// Applies fixture state at the composition root, before either destination appears.
    /// Normal launches must leave the library alone.
    static func prepareLaunch(destination: WatchAppLaunchLogic.Destination,
                              syncService: WatchSyncService) -> Bool {
        if destination != .library {
            let book = WatchAppLaunchLogic.crownDirectionFixture()
            syncService.library = WatchLibrary(books: [book], currentBookId: book.id)
        }
        return destination == .crownDirectionFixture
    }
    #endif

    var body: some Scene {
        WindowGroup {
            WatchAppRoot(syncService: syncService,
                         launchesCrownDirectionFixture: launchesCrownDirectionFixture)
        }
    }
}

/// Keeps launch activation on the library path. The RSVP fixture must retain its
/// in-memory book instead of loading the persisted library over it.
struct WatchAppRoot: View {
    @ObservedObject var syncService: WatchSyncService
    let launchesCrownDirectionFixture: Bool

    func appear() {
        if !launchesCrownDirectionFixture { syncService.activate() }
    }

    var body: some View {
        Group {
            if launchesCrownDirectionFixture {
                WatchRSVPView()
            } else {
                WatchLibraryView()
            }
        }
        .environmentObject(syncService)
        .onAppear(perform: appear)
    }
}
