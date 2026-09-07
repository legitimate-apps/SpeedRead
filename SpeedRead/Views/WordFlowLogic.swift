import CoreGraphics

nonisolated struct WordFlowArrangement {
    let size: CGSize
    let origins: [CGPoint]
}

/// Shared row breaks for measurement and placement, using each caller's available width.
nonisolated enum WordFlowLogic {
    static func arrange(
        sizes: [CGSize], width: CGFloat, hSpacing: CGFloat, vSpacing: CGFloat
    ) -> WordFlowArrangement {
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var origins: [CGPoint] = []

        for size in sizes {
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + vSpacing
                totalWidth = max(totalWidth, rowWidth - hSpacing)
                rowWidth = 0
                rowHeight = 0
            }
            origins.append(CGPoint(x: rowWidth, y: totalHeight))
            rowWidth += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - hSpacing)
        return WordFlowArrangement(
            size: CGSize(width: width.isFinite ? width : totalWidth, height: totalHeight),
            origins: origins
        )
    }
}
