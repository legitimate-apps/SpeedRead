//  SpineColor.swift
import SwiftUI

enum SpineColor {
    static let classicPalette: [Color] = [
        Color(red: 0x00/255.0, green: 0x5F/255.0, blue: 0x73/255.0),
        Color(red: 0x7B/255.0, green: 0x2D/255.0, blue: 0x26/255.0),
        Color(red: 0x2D/255.0, green: 0x4A/255.0, blue: 0x22/255.0),
        Color(red: 0x1B/255.0, green: 0x2A/255.0, blue: 0x4A/255.0),
        Color(red: 0x8B/255.0, green: 0x4A/255.0, blue: 0x2B/255.0),
        Color(red: 0x5B/255.0, green: 0x2C/255.0, blue: 0x5E/255.0),
        Color(red: 0x4A/255.0, green: 0x5A/255.0, blue: 0x6A/255.0),
        Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x2A/255.0),
        Color(red: 0x3E/255.0, green: 0x27/255.0, blue: 0x23/255.0),
        Color(red: 0x6B/255.0, green: 0x3A/255.0, blue: 0x2A/255.0),
    ]

    static func color(for title: String) -> Color {
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return classicPalette[abs(hash) % classicPalette.count]
    }
}
