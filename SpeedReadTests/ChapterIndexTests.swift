import Testing
@testable import SpeedRead

@Suite("Chapter index")
struct ChapterIndexTests {
    @Test func emptyIndexHasNoLookupOrNavigationResults() {
        let index = ChapterIndex([])

        #expect(index.chapter(containing: 0) == nil)
        #expect(index.next(after: 0) == nil)
        #expect(index.previous(before: 0) == nil)
    }

    @Test func singleChapterContainsEveryIndexAtAndPastItsBoundary() throws {
        let only = ChapterMark(title: "Only", startWordIndex: 0)
        let index = ChapterIndex([only])

        #expect(index.chapter(containing: 0) == only)
        #expect(index.chapter(containing: 10_000) == only)
        #expect(index.start(of: only) == 0)
        #expect(index.next(after: 0) == nil)
        #expect(index.previous(before: 0) == nil)
    }

    @Test func exactBoundaryBelongsToTheChapterThatStartsThere() throws {
        let first = ChapterMark(title: "First", startWordIndex: 0)
        let second = ChapterMark(title: "Second", startWordIndex: 8)
        let third = ChapterMark(title: "Third", startWordIndex: 20)
        let index = ChapterIndex([third, first, second])

        #expect(index.chapter(containing: 7) == first)
        #expect(index.chapter(containing: 8) == second)
        #expect(index.chapter(containing: 20) == third)
        #expect(index.chapter(containing: 999) == third)
        #expect(index.next(after: 8) == third)
        #expect(index.previous(before: 8) == first)
    }

    @Test func lookupBeforeFirstBoundaryHasNoContainingChapter() {
        let index = ChapterIndex([ChapterMark(title: "Late", startWordIndex: 5)])

        #expect(index.chapter(containing: 4) == nil)
        #expect(index.next(after: 4)?.title == "Late")
        #expect(index.previous(before: 5) == nil)
    }
}
