//  Theme.swift
import SwiftUI

extension Color {
    // MARK: - Core Palette
    static let walnut = Color(red: 0x3E / 255.0, green: 0x27 / 255.0, blue: 0x23 / 255.0)
    static let walnutLight = Color(red: 0x5D / 255.0, green: 0x40 / 255.0, blue: 0x37 / 255.0)
    static let parchment = Color(red: 0xFF / 255.0, green: 0xF8 / 255.0, blue: 0xE7 / 255.0)
    static let parchmentDark = Color(red: 0xF0 / 255.0, green: 0xE6 / 255.0, blue: 0xD0 / 255.0)
    static let inkBlack = Color(red: 0x1C / 255.0, green: 0x14 / 255.0, blue: 0x10 / 255.0)
    static let crimson = Color(red: 0xC6 / 255.0, green: 0x28 / 255.0, blue: 0x28 / 255.0)
    static let crimsonSoft = Color(red: 0xD4 / 255.0, green: 0x57 / 255.0, blue: 0x4A / 255.0)
    static let agedGold = Color(red: 0xC8 / 255.0, green: 0xA9 / 255.0, blue: 0x51 / 255.0)
    static let lamplight = Color(red: 0xFF / 255.0, green: 0xE0 / 255.0, blue: 0xA0 / 255.0)

    // MARK: - RSVP Mode
    static let rsvpBackground = Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x10 / 255.0)
    static let rsvpText = Color(red: 0xF5 / 255.0, green: 0xED / 255.0, blue: 0xE0 / 255.0)
}

// MARK: - Typography

extension Font {
    static func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func bodySerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func rsvpWord(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
