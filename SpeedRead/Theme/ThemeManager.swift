//
//  ThemeManager.swift
//  SpeedRead
//

import SwiftUI
import Observation

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    @ObservationIgnored private let defaults: UserDefaults

    var selectedThemeId: String {
        didSet {
            defaults.set(selectedThemeId, forKey: "selectedThemeId")
        }
    }

    var currentTheme: ShelfTheme {
        ShelfTheme.allThemes.first { $0.id == selectedThemeId } ?? .classic
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedThemeId = defaults.string(forKey: "selectedThemeId") ?? "classic"
    }
}
