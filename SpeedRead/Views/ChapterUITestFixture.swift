#if DEBUG
import Foundation

/// Deterministic navigation fixture, only requested by the explicit UI lane.
enum ChapterUITestFixture {
    static func book() -> Book? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--chapter-ui-fixture") else { return nil }
        let text = "Opening " + String(repeating: "beginning ", count: 39)
            + String(repeating: "\n\n" + String(repeating: "middle ", count: 40), count: 19)
            + "\n\nDestination " + String(repeating: "ending ", count: 79)
        let chapters: [ChapterMark] = arguments.contains("--chapter-ui-empty") ? [] : [
            .init(title: "Opening chapter", startWordIndex: 0),
            .init(title: "Destination chapter", startWordIndex: 800)
        ]
        return Book(title: "Chapter navigation fixture", author: "Test Library",
                    extractedText: text, sourceFileName: "fixture.txt", chapters: chapters)
    }
}
#endif
