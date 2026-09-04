import Foundation

/// Pure launch decisions for the watch app, including the DEBUG crown-direction UI fixture.
enum WatchAppLaunchLogic {
    static let crownDirectionArgument = "--ui-test-crown-direction"
    /// Seeds the fixture book into the library and shows the LIBRARY, not the RSVP surface, so a
    /// UI test can walk the real path a user takes: tap Now Reading -> RSVP presents.
    static let seededLibraryArgument = "--ui-test-seeded-library"

    enum Destination: Equatable {
        case library
        case seededLibrary
        case crownDirectionFixture
    }

    static func destination(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Destination {
        if arguments.contains(crownDirectionArgument) { return .crownDirectionFixture }
        if arguments.contains(seededLibraryArgument) { return .seededLibrary }
        return .library
    }

    static func crownDirectionFixture() -> WatchBook {
        let words = (0..<200).map { "word\(String(format: "%03d", $0))" }
        return WatchBook(
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
    }
}
