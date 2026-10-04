//
//  ContrastRatioTests.swift
//  SpeedReadTests
//

import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

@Suite("Contrast ratio")
struct ContrastRatioTests {
    @Test func blackOnWhiteIsTwentyOneToOne() {
        let ratio = ContrastRatio.ratio(
            foreground: .init(red: 0, green: 0, blue: 0),
            background: .init(red: 1, green: 1, blue: 1)
        )
        #expect(abs(ratio - 21) < 0.05)
    }

    @Test func ratioIsSymmetric() {
        let a = ContrastRatio.RGBA(red: 0.48, green: 0.29, blue: 0.17)
        let b = ContrastRatio.RGBA(red: 1, green: 0.97, blue: 0.91)
        #expect(
            abs(
                ContrastRatio.ratio(foreground: a, background: b)
                    - ContrastRatio.ratio(foreground: b, background: a)
            ) < 0.0001
        )
    }

    @Test func identicalColorsAreOneToOne() {
        let c = ContrastRatio.RGBA(red: 0.3, green: 0.4, blue: 0.5)
        #expect(abs(ContrastRatio.ratio(foreground: c, background: c) - 1) < 0.0001)
    }

    @Test func translucentForegroundIsCompositedOverBackground() {
        // Half-transparent black over white measures as 0.5-grey on white (~3.98:1),
        // not as opaque black on white (21:1).
        let ratio = ContrastRatio.ratio(
            foreground: .init(red: 0, green: 0, blue: 0, alpha: 0.5),
            background: .init(red: 1, green: 1, blue: 1)
        )
        #expect(ratio > 3.8 && ratio < 4.2)
    }

    @Test func luminanceUsesLinearizedChannelsBelowAndAboveThreshold() {
        // Channel at the 0.04045 knee takes the linear branch; 1.0 takes the power branch.
        let dark = ContrastRatio.luminance(.init(red: 0.04045, green: 0, blue: 0))
        #expect(abs(dark - 0.2126 * (0.04045 / 12.92)) < 0.0001)
        let white = ContrastRatio.luminance(.init(red: 1, green: 1, blue: 1))
        #expect(abs(white - 1) < 0.0001)
    }

    @Test func saddleOnParchmentMatchesComputedReference() {
        let ratio = ContrastRatio.ratio(
            foreground: .init(red: 0x7A / 255, green: 0x4A / 255, blue: 0x2B / 255),
            background: .init(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xE7 / 255)
        )
        #expect(abs(ratio - 6.98) < 0.05)
    }
}

@Suite("App palette contrast")
struct AppPaletteContrastTests {
    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> ContrastRatio.RGBA {
        let uiColor = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ContrastRatio.RGBA(red: r, green: g, blue: b, alpha: a)
    }

    private func ratio(_ fg: Color, _ bg: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        ContrastRatio.ratio(foreground: resolve(fg, style), background: resolve(bg, style))
    }

    @Test func textTokenPairsClearFourPointFiveInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(ratio(.appInk, .appSurface, style) >= 4.5, "appInk on appSurface \(style)")
            #expect(ratio(.appInkSecondary, .appSurface, style) >= 4.5, "appInkSecondary on appSurface \(style)")
            #expect(ratio(.appInk, .appSurfaceRaised, style) >= 4.5, "appInk on appSurfaceRaised \(style)")
            #expect(ratio(.appInkSecondary, .appSurfaceRaised, style) >= 4.5, "appInkSecondary on appSurfaceRaised \(style)")
            #expect(ratio(.appAccent, .appSurface, style) >= 4.5, "appAccent on appSurface \(style)")
            #expect(ratio(.appAccent, .appSurfaceRaised, style) >= 4.5, "appAccent on appSurfaceRaised \(style)")
            #expect(ratio(.appOnAccent, .appAccent, style) >= 4.5, "appOnAccent on appAccent \(style)")
            #expect(ratio(.appGoldText, .appSurface, style) >= 4.5, "appGoldText on appSurface \(style)")
            #expect(ratio(.pivot, .appSurface, style) >= 4.5, "pivot on appSurface \(style)")
            #expect(ratio(.appError, .appSurface, style) >= 4.5, "appError on appSurface \(style)")
            #expect(ratio(.appError, .appSurfaceRaised, style) >= 4.5, "appError on appSurfaceRaised \(style)")
            #expect(ratio(.appSuccess, .appSurface, style) >= 4.5, "appSuccess on appSurface \(style)")
            #expect(ratio(.appSuccess, .appSurfaceRaised, style) >= 4.5, "appSuccess on appSurfaceRaised \(style)")
        }
    }

    @Test func tokenValuesMatchTheShippedPalette() {
        #expect(assertChannels(resolve(.appAccent, .light), red: 0x7A, green: 0x4A, blue: 0x2B))
        #expect(assertChannels(resolve(.appAccent, .dark), red: 0xD9, green: 0xB9, blue: 0x68))
        #expect(assertChannels(resolve(.appSurface, .light), red: 0xFF, green: 0xF8, blue: 0xE7))
        #expect(assertChannels(resolve(.appSurface, .dark), red: 0x1A, green: 0x12, blue: 0x10))
        #expect(assertChannels(resolve(.appSurfaceRaised, .light), red: 0xF0, green: 0xE6, blue: 0xD0))
        #expect(assertChannels(resolve(.appSurfaceRaised, .dark), red: 0x25, green: 0x1A, blue: 0x14))
        #expect(assertChannels(resolve(.appInk, .light), red: 0x1C, green: 0x14, blue: 0x10))
        #expect(assertChannels(resolve(.appInk, .dark), red: 0xF5, green: 0xED, blue: 0xE0))
        #expect(assertChannels(resolve(.appInkSecondary, .light), red: 0x5D, green: 0x40, blue: 0x37))
        #expect(assertChannels(resolve(.appInkSecondary, .dark), red: 0xB9, green: 0xA9, blue: 0x8F))
        #expect(assertChannels(resolve(.appOnAccent, .light), red: 0xFF, green: 0xF8, blue: 0xE7))
        #expect(assertChannels(resolve(.appOnAccent, .dark), red: 0x1A, green: 0x12, blue: 0x10))
        #expect(assertChannels(resolve(.appGoldText, .light), red: 0x8A, green: 0x6A, blue: 0x1F))
        #expect(assertChannels(resolve(.appGoldText, .dark), red: 0xD9, green: 0xB9, blue: 0x68))
        #expect(assertChannels(resolve(.pivot, .light), red: 0xB3, green: 0x26, blue: 0x1E))
        #expect(assertChannels(resolve(.pivot, .dark), red: 0xE2, green: 0x57, blue: 0x4C))
        #expect(assertChannels(resolve(.appError, .light), red: 0xA2, green: 0x3B, blue: 0x2A))
        #expect(assertChannels(resolve(.appError, .dark), red: 0xE8, green: 0x80, blue: 0x6F))
        #expect(assertChannels(resolve(.appSuccess, .light), red: 0x4F, green: 0x6B, blue: 0x3A))
        #expect(assertChannels(resolve(.appSuccess, .dark), red: 0x9D, green: 0xBE, blue: 0x7E))
    }

    private func assertChannels(
        _ color: ContrastRatio.RGBA,
        red: Int,
        green: Int,
        blue: Int
    ) -> Bool {
        abs(color.red - CGFloat(red) / 255) < 0.01
            && abs(color.green - CGFloat(green) / 255) < 0.01
            && abs(color.blue - CGFloat(blue) / 255) < 0.01
            && color.alpha == 1
    }
}
