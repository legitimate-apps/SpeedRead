import CoreGraphics
import Testing
@testable import SpeedRead

@Suite("Adaptive library shelf layout")
struct LibraryLayoutMetricsTests {
    @Test("Compact phone preserves four books and shipping dimensions")
    func compactPhone() {
        let metrics = LibraryLayoutMetrics(isRegularWidth: false, containerWidth: 393)

        #expect(metrics.booksPerShelf == 4)
        #expect(metrics.spineWidth == 60)
        #expect(metrics.minimumSpineHeight == 120)
        #expect(metrics.maximumSpineHeight == 180)
        #expect(metrics.titleFontSize == 9)
        #expect(metrics.authorFontSize == 7)
        // Sparse compact libraries fill the viewport with empty shelves too (warm-palette
        // restyle): (852 - 16 + 24) / (120 + 12 + 24) = 5.51 -> 6.
        #expect(metrics.minimumVisibleShelfCount(viewportHeight: 852) == 6)
    }

    @Test("iPad portrait capacity is derived from width")
    func iPadPortrait() {
        let metrics = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_024)

        #expect(metrics.booksPerShelf == 7)
        #expect(metrics.spineWidth == 112)
        #expect(metrics.minimumSpineHeight == 224)
        #expect(metrics.maximumSpineHeight == 300)
        #expect(metrics.titleFontSize == 15)
        #expect(metrics.authorFontSize == 12)
        #expect(metrics.shelfSpacing == 0)
        #expect(metrics.minimumVisibleShelfCount(viewportHeight: 1_300) == 5)
    }

    @Test("iPad landscape gains capacity and honors the content cap")
    func iPadLandscape() {
        let portrait = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_024)
        let landscape = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_366)
        let stageManagerWide = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_800)

        #expect(landscape.booksPerShelf > portrait.booksPerShelf)
        #expect(landscape.booksPerShelf == 8)
        #expect(stageManagerWide.booksPerShelf == landscape.booksPerShelf)
    }

    @Test("Sparse regular-width library requests decorative fill shelves")
    func sparseLibrary() {
        let metrics = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_024)
        let shelves = metrics.shelves(for: Array(0..<4))
        let visibleCount = max(
            shelves.count,
            metrics.minimumVisibleShelfCount(viewportHeight: 1_300)
        )

        #expect(shelves.count == 1)
        #expect(visibleCount == 5)
    }

    @Test("Overflow chunks into a second shelf")
    func overflowShelf() {
        let metrics = LibraryLayoutMetrics(isRegularWidth: true, containerWidth: 1_024)
        let shelves = metrics.shelves(for: Array(0..<8))

        #expect(shelves.count == 2)
        #expect(shelves[0].count == 7)
        #expect(shelves[1].count == 1)
    }
}
