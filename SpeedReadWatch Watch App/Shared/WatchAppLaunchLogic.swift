import Foundation

/// Pure launch decisions for the watch app, including the DEBUG crown-direction UI fixture.
enum WatchAppLaunchLogic {
    static let crownDirectionArgument = "--ui-test-crown-direction"

    enum Destination: Equatable {
        case library
        case crownDirectionFixture
    }

    static func destination(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Destination {
        arguments.contains(crownDirectionArgument) ? .crownDirectionFixture : .library
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
