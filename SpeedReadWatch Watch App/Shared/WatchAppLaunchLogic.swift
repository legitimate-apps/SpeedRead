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
        // TDD scaffold: the red test proves the launch argument selects the fixture.
        .library
    }

    static func crownDirectionFixture() -> WatchBook {
        // TDD scaffold: the red test pins the deterministic fixture the watch UI lane depends on.
        WatchBook(
            id: UUID(uuidString: "C0DEC0DE-0000-4000-8000-000000000008")!,
            title: "",
            author: "",
            text: "",
            lastReadIndex: 0,
            lastReadDate: nil,
            browseWordIndex: 0,
            furthestReadWordIndex: 0,
            wordCount: 0,
            dateAdded: Date(timeIntervalSince1970: 0)
        )
    }
}
