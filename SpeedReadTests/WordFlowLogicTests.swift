import CoreGraphics
import Testing
@testable import SpeedRead

@Suite("Word flow wrap math")
struct WordFlowLogicTests {
    @Test func oversizedFirstWordDoesNotCreateAnEmptyRow() {
        // Mutation: remove rowWidth > 0; an oversized first word then starts below an empty row.
        let result = WordFlowLogic.arrange(
            sizes: [CGSize(width: 80, height: 12)], width: 50, hSpacing: 4, vSpacing: 6
        )
        #expect(result.origins == [.zero])
        #expect(result.size == CGSize(width: 50, height: 12))
    }

    @Test func exactFitStaysOnTheRow() {
        // Mutation: replace > with >= at the wrap boundary; the second word moves down.
        let result = WordFlowLogic.arrange(
            sizes: [CGSize(width: 20, height: 10), CGSize(width: 26, height: 8)],
            width: 50, hSpacing: 4, vSpacing: 6
        )
        #expect(result.origins == [.zero, CGPoint(x: 24, y: 0)])
        #expect(result.size == CGSize(width: 50, height: 10))
    }

    @Test func wrappedRowsUseTallestWordAndVerticalSpacing() {
        // Mutations: omit vSpacing, use the last word's height, or fail to reset rowHeight.
        let result = WordFlowLogic.arrange(
            sizes: [CGSize(width: 20, height: 12), CGSize(width: 20, height: 7),
                    CGSize(width: 30, height: 5), CGSize(width: 30, height: 9)],
            width: 50, hSpacing: 4, vSpacing: 6
        )
        #expect(result.origins == [.zero, CGPoint(x: 24, y: 0),
                                   CGPoint(x: 0, y: 18), CGPoint(x: 0, y: 29)])
        #expect(result.size == CGSize(width: 50, height: 38))
    }

    @Test func intrinsicWidthExcludesTrailingSpacing() {
        // Mutation: remove the - hSpacing trailing correction; intrinsic width grows by four.
        let result = WordFlowLogic.arrange(
            sizes: [CGSize(width: 20, height: 12), CGSize(width: 26, height: 8)],
            width: .infinity, hSpacing: 4, vSpacing: 6
        )
        #expect(result.size == CGSize(width: 50, height: 12))
        #expect(result.origins == [.zero, CGPoint(x: 24, y: 0)])
    }

    @Test func placementRecomputesRowsWhenItsWidthDiffersFromMeasurement() {
        // Mutation: ignore the supplied width (compare against infinity); the narrower call no longer wraps.
        let sizes = [CGSize(width: 20, height: 12), CGSize(width: 26, height: 8)]
        let measured = WordFlowLogic.arrange(sizes: sizes, width: 50, hSpacing: 4, vSpacing: 6)
        let placed = WordFlowLogic.arrange(sizes: sizes, width: 49, hSpacing: 4, vSpacing: 6)
        #expect(measured.origins == [.zero, CGPoint(x: 24, y: 0)])
        #expect(measured.size == CGSize(width: 50, height: 12))
        #expect(placed.origins == [.zero, CGPoint(x: 0, y: 18)])
        #expect(placed.size == CGSize(width: 49, height: 26))
    }

    @Test func emptyContentRetainsFiniteProposalButHasNoIntrinsicSize() {
        // Mutations: always return totalWidth, or let the final trailing correction make width negative.
        let finite = WordFlowLogic.arrange(sizes: [], width: 50, hSpacing: 4, vSpacing: 6)
        let intrinsic = WordFlowLogic.arrange(sizes: [], width: .infinity, hSpacing: 4, vSpacing: 6)
        #expect(finite.size == CGSize(width: 50, height: 0))
        #expect(intrinsic.size == .zero)
        #expect(finite.origins.isEmpty)
        #expect(intrinsic.origins.isEmpty)
    }
}
