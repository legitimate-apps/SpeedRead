import Foundation
@testable import SpeedReadWatch_Watch_App

/// Every fixture owns a directory, including the legacy migration source, independent of plans.
final class WatchTestStorage {
    let directory: URL
    var store: WatchLibraryStore {
        WatchLibraryStore(fileURL: directory.appendingPathComponent("watchlibrary.json"))
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
