//
//  ThemeTests.swift
//  SpeedReadTests
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import SpeedRead

@Suite("Theme Manager Tests")
@MainActor
struct ThemeTests {
    private let storage = IsolatedDefaults()

    @Test func allThemesHaveUniqueIds() {
        let ids = ShelfTheme.allThemes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func classicThemeIsDefault() {
        let manager = ThemeManager(defaults: storage.defaults)
        #expect(manager.currentTheme.id == "classic")
    }

    @Test func canSwitchTheme() {
        let manager = ThemeManager(defaults: storage.defaults)
        manager.selectedThemeId = "midnight"
        #expect(manager.currentTheme.id == "midnight")
        #expect(manager.currentTheme.name == "Midnight Library")
    }

    @Test func invalidThemeIdFallsBackToClassic() {
        let manager = ThemeManager(defaults: storage.defaults)
        manager.selectedThemeId = "nonexistent"
        #expect(manager.currentTheme.id == "classic")
    }

    @Test func allThemesHaveSpineColors() {
        for theme in ShelfTheme.allThemes {
            #expect(!theme.spineColors.isEmpty, "Theme \(theme.name) has no spine colors")
        }
    }

    @Test func spineColorWithPaletteIsDeterministic() {
        let palette = ShelfTheme.classic.spineColors
        let color1 = SpineColor.color(for: "Test Book", from: palette)
        let color2 = SpineColor.color(for: "Test Book", from: palette)
        #expect(color1 == color2)
    }

    @Test func fourThemesShipped() {
        #expect(ShelfTheme.allThemes.count == 4)
    }

    @Test func readerThemeModePalettesMatchTheShippedReaderStyleAndContrastGuidelines() {
        for mode in ReaderThemeMode.allCases {
            let palette = mode.palette
            let expected = expectedPalette(for: mode)

            #expect(palette.toolbarColorScheme == expected.toolbarColorScheme)
            assertColor(palette.background, equals: expected.background)
            assertColor(palette.titleText, equals: expected.titleText)
            assertColor(palette.bodyText, equals: expected.bodyText)
            assertColor(palette.headerText, equals: expected.headerText)
            assertColor(palette.accent, equals: expected.accent)
            assertColor(palette.barBackground, equals: expected.barBackground)
            assertColor(palette.barText, equals: expected.barText)

            #expect(contrastRatio(foreground: palette.titleText, background: palette.background) >= 4.5)
            #expect(contrastRatio(foreground: palette.bodyText, background: palette.background) >= 4.5)
            #expect(contrastRatio(foreground: palette.barText, background: palette.barBackground) >= 4.5)
        }

        #expect(ReaderThemeMode.allCases.map(\.rawValue).count == 3)
    }

    private func expectedPalette(for mode: ReaderThemeMode) -> ReaderPalette {
        switch mode {
        case .parchment:
            return ReaderPalette(
                background: Color.parchment,
                titleText: Color.inkBlack,
                bodyText: Color.inkBlack.opacity(0.92),
                headerText: Color.inkBlack.opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color.parchment.opacity(0.92),
                barText: Color.inkBlack.opacity(0.78),
                toolbarColorScheme: .light
            )
        case .sepia:
            return ReaderPalette(
                background: Color(red: 0xF7 / 255, green: 0xEB / 255, blue: 0xCF / 255),
                titleText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255),
                bodyText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.92),
                headerText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color(red: 0xF1 / 255, green: 0xE3 / 255, blue: 0xC2 / 255).opacity(0.94),
                barText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.8),
                toolbarColorScheme: .light
            )
        case .night:
            return ReaderPalette(
                background: Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x12 / 255),
                titleText: Color(red: 0xF1 / 255, green: 0xEC / 255, blue: 0xDD / 255),
                bodyText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.92),
                headerText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.85),
                accent: Color.crimsonSoft,
                barBackground: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255).opacity(0.94),
                barText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.85),
                toolbarColorScheme: .dark
            )
        }
    }

    private func assertColor(
        _ actual: Color,
        equals expected: Color,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (ar, ag, ab, aa) = rgba(actual)
        let (er, eg, eb, ea) = rgba(expected)
        #expect(
            abs(ar - er) <= 0.015 &&
            abs(ag - eg) <= 0.015 &&
            abs(ab - eb) <= 0.015 &&
            abs(aa - ea) <= 0.02,
            "Color mismatch",
            sourceLocation: sourceLocation
        )
    }

    private func rgba(_ color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let uiColor = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func luminance(_ color: Color) -> CGFloat {
        let (r, g, b, _) = rgba(color)
        let adjust: (CGFloat) -> CGFloat = {
            if $0 <= 0.03928 {
                return $0 / 12.92
            }
            return pow(($0 + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * adjust(r) + 0.7152 * adjust(g) + 0.0722 * adjust(b)
    }

    private func contrastRatio(foreground: Color, background: Color) -> CGFloat {
        let l1 = luminance(foreground)
        let l2 = luminance(background)
        let bright = max(l1, l2)
        let dark = min(l1, l2)
        return (bright + 0.05) / (dark + 0.05)
    }
}
