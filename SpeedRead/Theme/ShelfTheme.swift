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

    static let allThemes: [ShelfTheme] = [classic, midnight, modern, vintage]

    static let classic = ShelfTheme(
        id: "classic", name: "Classic",
        spineColors: [
            Color(red: 0x00/255, green: 0x5F/255, blue: 0x73/255),
            Color(red: 0x7B/255, green: 0x2D/255, blue: 0x26/255),
            Color(red: 0x2D/255, green: 0x4A/255, blue: 0x22/255),
            Color(red: 0x1B/255, green: 0x2A/255, blue: 0x4A/255),
            Color(red: 0x8B/255, green: 0x4A/255, blue: 0x2B/255),
            Color(red: 0x5B/255, green: 0x2C/255, blue: 0x5E/255),
            Color(red: 0x4A/255, green: 0x5A/255, blue: 0x6A/255),
            Color(red: 0x8B/255, green: 0x73/255, blue: 0x2A/255),
            Color(red: 0x3E/255, green: 0x27/255, blue: 0x23/255),
            Color(red: 0x6B/255, green: 0x3A/255, blue: 0x2A/255),
        ],
        spineTextColor: Color.parchment,
        shelfColor: Color.walnut,
        shelfHighlightColor: Color.lamplight,
        backgroundColor: Color.parchment,
        fontDesign: .serif
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
        shelfColor: Color(red: 0x2A/255, green: 0x1E/255, blue: 0x1A/255),
        shelfHighlightColor: Color(red: 0x4A/255, green: 0x4A/255, blue: 0x6A/255),
        backgroundColor: Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255),
        fontDesign: .serif
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
        shelfColor: Color(red: 0xE8/255, green: 0xE4/255, blue: 0xE0/255),
        shelfHighlightColor: .white,
        backgroundColor: Color(red: 0xF8/255, green: 0xF6/255, blue: 0xF4/255),
        fontDesign: .default
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
        fontDesign: .serif
    )
}
