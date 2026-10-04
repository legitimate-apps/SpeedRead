import SwiftUI

/// Shared shelf measurements. Compact-width values intentionally preserve the
/// shipping iPhone layout; regular width presents the shelf as iPad furniture.
nonisolated struct LibraryLayoutMetrics: Equatable {
    static let maximumBookContentWidth: CGFloat = 1_200

    let isRegularWidth: Bool
    let containerWidth: CGFloat

    var spineWidth: CGFloat { isRegularWidth ? 112 : 60 }
    var minimumSpineHeight: CGFloat { isRegularWidth ? 224 : 120 }
    var maximumSpineHeight: CGFloat { isRegularWidth ? 300 : 180 }
    var bookSpacing: CGFloat { isRegularWidth ? 16 : 8 }
    var titleFontSize: CGFloat { isRegularWidth ? 15 : 9 }
    var authorFontSize: CGFloat { isRegularWidth ? 12 : 7 }
    var horizontalInset: CGFloat { isRegularWidth ? 30 : 16 }
    var shelfSpacing: CGFloat { isRegularWidth ? 0 : 24 }
    var shelfPlankHeight: CGFloat { isRegularWidth ? 16 : 12 }
    var sideRailWidth: CGFloat { isRegularWidth ? 18 : 0 }

    /// Capacity is derived from the centered book-content column. The compact
    /// cap retains the current four-books-per-row iPhone appearance, including
    /// on a compact-width phone in landscape.
    var booksPerShelf: Int {
        let usableWidth = max(
            0,
            min(containerWidth, Self.maximumBookContentWidth) - (horizontalInset * 2)
        )
        let computed = max(1, Int(floor(usableWidth / (spineWidth + bookSpacing))))
        return isRegularWidth ? computed : min(4, computed)
    }

    /// Bay height an empty shelf still claims, so fill shelves look like shelves.
    /// Compact uses the SHORTEST spine: populated rows already stand at least that
    /// tall, so the lift only ever affects empty shelves.
    var emptyShelfBayHeight: CGFloat {
        isRegularWidth ? maximumSpineHeight : minimumSpineHeight
    }

    func shelves<BookElement>(for books: [BookElement]) -> [[BookElement]] {
        stride(from: 0, to: books.count, by: booksPerShelf).map { start in
            Array(books[start..<min(start + booksPerShelf, books.count)])
        }
    }

    /// Sparse libraries extend empty shelf rows to the bottom of the viewport, on
    /// both size classes — a one-row library reads as a bookcase, not a bare page.
    func minimumVisibleShelfCount(viewportHeight: CGFloat) -> Int {
        let availableHeight = max(0, viewportHeight - 16)
        let rowStride = emptyShelfBayHeight + shelfPlankHeight + shelfSpacing
        return max(1, Int(ceil((availableHeight + shelfSpacing) / rowStride)))
    }
}

/// Places every book in an equal slot. Regular-width sparse shelves use the
/// full centered content column; compact shelves retain their leading cluster.
struct EqualShelfSlotLayout: Layout {
    let metrics: LibraryLayoutMetrics

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let proposedWidth = proposal.width ?? 0
        let contentHeight = subviews.reduce(CGFloat.zero) { height, subview in
            max(height, subview.sizeThatFits(.unspecified).height)
        }
        return CGSize(width: proposedWidth, height: max(contentHeight, metrics.emptyShelfBayHeight))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let slotWidth: CGFloat
        let contentOriginX: CGFloat

        if metrics.isRegularWidth {
            let contentWidth = min(bounds.width, LibraryLayoutMetrics.maximumBookContentWidth)
            slotWidth = contentWidth / CGFloat(subviews.count)
            contentOriginX = bounds.minX + ((bounds.width - contentWidth) / 2)
        } else {
            slotWidth = metrics.spineWidth + metrics.bookSpacing
            contentOriginX = bounds.minX
        }

        let bookProposal = ProposedViewSize(
            width: min(slotWidth, metrics.spineWidth),
            height: nil
        )

        for (index, subview) in subviews.enumerated() {
            let centerX = contentOriginX + (CGFloat(index) + 0.5) * slotWidth
            subview.place(
                at: CGPoint(x: centerX, y: bounds.maxY),
                anchor: .bottom,
                proposal: bookProposal
            )
        }
    }
}
