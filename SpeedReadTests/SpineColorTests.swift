//
//  SpineColorTests.swift
//  SpeedReadTests
//

import SwiftUI
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

struct SpineColorTests {
    @Test func sameTitle_returnsSameIndex() {
        // Mutation: replace stable title hashing with per-call randomness.
        let index1 = SpineColor.colorIndex(for: "Alice in Wonderland")
        let index2 = SpineColor.colorIndex(for: "Alice in Wonderland")
        #expect(index1 == index2)
    }

    @Test func differentTitles_canReturnDifferentIndices() {
        // Mutation: return a constant color index for every title.
        let titles = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon",
                      "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda"]
        let indices = Set(titles.map { SpineColor.colorIndex(for: $0) })
        #expect(indices.count > 1)
    }

    @Test func colorIndex_withinRange() {
        // Mutation: omit the palette-count modulo, returning the full hash as an index.
        let index = SpineColor.colorIndex(for: "Test Book")
        #expect(index >= 0)
        #expect(index < SpineColor.spineColors.count)
    }
    @Test func defaultAndEmptyPalettesResolveTheTitleColor() {
        // Mutation: use a fixed/default index, or fail to fall back for an empty palette.
        #expect(SpineColor.color(for: "A") == SpineColor.spineColors[5])
        #expect(SpineColor.color(for: "B", from: []) == SpineColor.spineColors[6])
    }

    @Test func customPaletteUsesItsOwnCountAndStableTitleHash() {
        // Mutation: ignore the supplied palette, use the stock palette count, or drop hash accumulation.
        let palette: [Color] = [.red, .green, .blue]
        // "AB": 65 * 31 + 66 = 2081, remainder 2; "AC" advances to remainder 0.
        #expect(SpineColor.color(for: "AB", from: palette) == .blue)
        #expect(SpineColor.color(for: "AC", from: palette) == .red)
    }
}
