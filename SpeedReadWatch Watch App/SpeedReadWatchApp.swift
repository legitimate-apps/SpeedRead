import SwiftUI

@main
struct SpeedReadWatch_Watch_AppApp: App {
    @StateObject private var syncService = WatchSyncService.shared
    private let launchesCrownDirectionFixture: Bool

    init() {
        #if DEBUG
        launchesCrownDirectionFixture = ProcessInfo.processInfo.arguments
            .contains("--ui-test-crown-direction")
        if launchesCrownDirectionFixture {
            let words = (0..<200).map { "word\(String(format: "%03d", $0))" }
            let book = WatchBook(
                id: UUID(uuidString: "C0DEC0DE-0000-4000-8000-000000000008")!,
                title: "Crown Direction Fixture",
                author: "SpeedRead",
                text: words.joined(separator: " "),
                lastReadIndex: 100,
                lastReadDate: nil,
                browseWordIndex: 100,
                furthestReadWordIndex: 100,
                wordCount: words.count,
                dateAdded: Date(timeIntervalSince1970: 0)
            )
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
