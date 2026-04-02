//
//  ThemeTests.swift
//  SpeedReadTests
//

import Testing
import Foundation
@testable import SpeedRead

@Suite("Theme Manager Tests")
struct ThemeTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "selectedThemeId")
    }

    @Test func allThemesHaveUniqueIds() {
        let ids = ShelfTheme.allThemes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func classicThemeIsDefault() {
        let manager = ThemeManager()
        #expect(manager.currentTheme.id == "classic")
    }

    @Test func canSwitchTheme() {
        let manager = ThemeManager()
        manager.selectedThemeId = "midnight"
        #expect(manager.currentTheme.id == "midnight")
        #expect(manager.currentTheme.name == "Midnight Library")
    }

    @Test func invalidThemeIdFallsBackToClassic() {
        let manager = ThemeManager()
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
}
