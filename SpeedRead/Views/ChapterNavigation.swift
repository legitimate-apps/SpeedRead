import Foundation

/// Presentation over the existing chapter coordinate space; never retokenizes a book.
nonisolated struct ChapterNavigation {
    let rows: [ChapterMark]
    private let index: ChapterIndex

    init(chapters: [ChapterMark]) {
        // Preserve source order at equal offsets, including empty spine items.
        rows = chapters.enumerated().sorted {
            if $0.element.startWordIndex == $1.element.startWordIndex {
                return $0.offset < $1.offset
            }
            return $0.element.startWordIndex < $1.element.startWordIndex
        }.map(\.element)
        index = ChapterIndex(chapters)
    }

    func current(at wordIndex: Int) -> ChapterMark? {
        index.chapter(containing: wordIndex)
    }

    func isCurrent(row: Int, at wordIndex: Int) -> Bool {
        // Only the final row at a shared offset owns words, even for identical marks.
        guard let chapter = current(at: wordIndex) else { return false }
        return rows.indices.contains(row) && row == rows.lastIndex(of: chapter)
    }
}
