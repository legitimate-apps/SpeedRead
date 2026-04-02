//
//  SpineColorTests.swift
//  SpeedReadTests
//

import Testing
@testable import SpeedRead

struct SpineColorTests {
    @Test func sameTitle_returnsSameIndex() {
        let index1 = SpineColor.colorIndex(for: "Alice in Wonderland")
        let index2 = SpineColor.colorIndex(for: "Alice in Wonderland")
        #expect(index1 == index2)
    }

    @Test func differentTitles_canReturnDifferentIndices() {
        let titles = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon",
                      "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda"]
        let indices = Set(titles.map { SpineColor.colorIndex(for: $0) })
        #expect(indices.count > 1)
    }

    @Test func colorIndex_withinRange() {
        let index = SpineColor.colorIndex(for: "Test Book")
        #expect(index >= 0)
        #expect(index < SpineColor.spineColors.count)
    }
}
