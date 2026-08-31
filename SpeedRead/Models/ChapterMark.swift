import Foundation

nonisolated struct ChapterMark: Codable, Hashable, Sendable {
    let title: String
    let startWordIndex: Int
}

nonisolated struct ChapterIndex: Sendable {
    private let marks: [ChapterMark]

    init(_ marks: [ChapterMark]) {
        self.marks = marks.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.startWordIndex == rhs.element.startWordIndex {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.startWordIndex < rhs.element.startWordIndex
            }
            .map(\.element)
    }

    func chapter(containing wordIndex: Int) -> ChapterMark? {
        marks.last { $0.startWordIndex <= wordIndex }
    }

    func start(of chapter: ChapterMark) -> Int? {
        marks.contains(chapter) ? chapter.startWordIndex : nil
    }

    func next(after wordIndex: Int) -> ChapterMark? {
        marks.first { $0.startWordIndex > wordIndex }
    }

    func previous(before wordIndex: Int) -> ChapterMark? {
        marks.last { $0.startWordIndex < wordIndex }
    }
}
