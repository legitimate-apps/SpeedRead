//
//  ThemeManager.swift
//  SpeedRead
//

import SwiftUI
import Observation

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var selectedThemeId: String {
        didSet {
            UserDefaults.standard.set(selectedThemeId, forKey: "selectedThemeId")
        }
    }

    var currentTheme: ShelfTheme {
        ShelfTheme.allThemes.first { $0.id == selectedThemeId } ?? .classic
    }

    init() {
        self.selectedThemeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "classic"
    }
}
