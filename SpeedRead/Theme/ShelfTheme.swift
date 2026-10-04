//
//  ShelfTheme.swift
//  SpeedRead
//

import SwiftUI

struct ShelfTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let spineColors: [Color]
    let spineTextColor: Color
    let shelfColor: Color
    let shelfHighlightColor: Color
    let backgroundColor: Color
    let fontDesign: Font.Design
    /// Whether the shelf background itself is dark. Drives the library's nav-bar color
    /// scheme and card labels, so chrome stays legible over the theme in EITHER OS
    /// appearance — the shelf keeps its character, the OS toggle does not restyle it.
    let isDark: Bool

    var toolbarColorScheme: ColorScheme { isDark ? .dark : .light }

    /// Primary text drawn directly on the shelf background (nav titles, empty states).
    var chromeText: Color { isDark ? .rsvpText : .walnut }

    /// Accent drawn on the shelf background (toolbar icons, calls to action).
    var chromeAccent: Color {
        isDark
            ? Color(red: 0xD9 / 255, green: 0xB9 / 255, blue: 0x68 / 255)
            : Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x2B / 255)
    }

    /// Text drawn on a `chromeAccent` fill.
    var chromeOnAccent: Color { isDark ? .rsvpBackground : .parchment }

    static let allThemes: [ShelfTheme] = [classic, midnight, modern, vintage]

    static let classic = ShelfTheme(
        id: "classic", name: "Classic",
        spineColors: SpineColor.spineColors,
        spineTextColor: Color.parchment,
        shelfColor: Color.walnut,
        shelfHighlightColor: Color.lamplight,
        backgroundColor: Color.parchment,
        fontDesign: .serif,
        isDark: false
    )

    static let midnight = ShelfTheme(
        id: "midnight", name: "Midnight Library",
        spineColors: [
            Color(red: 0x1A/255, green: 0x3C/255, blue: 0x5E/255),
            Color(red: 0x5C/255, green: 0x1A/255, blue: 0x3B/255),
            Color(red: 0x1A/255, green: 0x4D/255, blue: 0x3E/255),
            Color(red: 0x3D/255, green: 0x1A/255, blue: 0x5C/255),
            Color(red: 0x5C/255, green: 0x3D/255, blue: 0x1A/255),
            Color(red: 0x1A/255, green: 0x1A/255, blue: 0x4D/255),
            Color(red: 0x4D/255, green: 0x1A/255, blue: 0x1A/255),
            Color(red: 0x2E/255, green: 0x4A/255, blue: 0x5A/255),
            Color(red: 0x3A/255, green: 0x2A/255, blue: 0x4A/255),
            Color(red: 0x4A/255, green: 0x3A/255, blue: 0x2A/255),
        ],
        spineTextColor: Color(red: 0xD4/255, green: 0xD0/255, blue: 0xC8/255),
        shelfColor: Color(red: 0x4A/255, green: 0x34/255, blue: 0x26/255),
        shelfHighlightColor: Color.agedGold,
        backgroundColor: Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255),
        fontDesign: .serif,
        isDark: true
    )

    static let modern = ShelfTheme(
        id: "modern", name: "Modern Minimal",
        spineColors: [
            Color(red: 0xB8/255, green: 0xC4/255, blue: 0xCA/255),
            Color(red: 0xD4/255, green: 0xA5/255, blue: 0xA5/255),
            Color(red: 0xA5/255, green: 0xC4/255, blue: 0xB8/255),
            Color(red: 0xC4/255, green: 0xB8/255, blue: 0xA5/255),
            Color(red: 0xA5/255, green: 0xA5/255, blue: 0xC4/255),
            Color(red: 0xC4/255, green: 0xC4/255, blue: 0xB8/255),
            Color(red: 0xB8/255, green: 0xA5/255, blue: 0xC4/255),
            Color(red: 0xA5/255, green: 0xB8/255, blue: 0xB8/255),
            Color(red: 0xD4/255, green: 0xC4/255, blue: 0xA5/255),
            Color(red: 0xC4/255, green: 0xA5/255, blue: 0xB8/255),
        ],
        spineTextColor: Color(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255),
        shelfColor: Color(red: 0xD8/255, green: 0xD2/255, blue: 0xC8/255),
        shelfHighlightColor: .white,
        backgroundColor: Color(red: 0xF8/255, green: 0xF6/255, blue: 0xF4/255),
        fontDesign: .default,
        isDark: false
    )

    static let vintage = ShelfTheme(
        id: "vintage", name: "Vintage",
        spineColors: [
            Color(red: 0x8B/255, green: 0x73/255, blue: 0x55/255),
            Color(red: 0x6B/255, green: 0x7B/255, blue: 0x5B/255),
            Color(red: 0x8B/255, green: 0x5B/255, blue: 0x4B/255),
            Color(red: 0x5B/255, green: 0x6B/255, blue: 0x7B/255),
            Color(red: 0x7B/255, green: 0x5B/255, blue: 0x6B/255),
            Color(red: 0x6B/255, green: 0x6B/255, blue: 0x5B/255),
            Color(red: 0x8B/255, green: 0x6B/255, blue: 0x5B/255),
            Color(red: 0x5B/255, green: 0x7B/255, blue: 0x6B/255),
            Color(red: 0x7B/255, green: 0x6B/255, blue: 0x5B/255),
            Color(red: 0x6B/255, green: 0x5B/255, blue: 0x5B/255),
        ],
        spineTextColor: Color(red: 0xF5/255, green: 0xEB/255, blue: 0xD5/255),
        shelfColor: Color(red: 0x5D/255, green: 0x47/255, blue: 0x37/255),
        shelfHighlightColor: Color(red: 0xD4/255, green: 0xC0/255, blue: 0x90/255),
        backgroundColor: Color(red: 0xF5/255, green: 0xE6/255, blue: 0xC8/255),
        fontDesign: .serif,
        isDark: false
    )
}
