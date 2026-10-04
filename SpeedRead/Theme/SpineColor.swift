//
//  SpineColor.swift
//  SpeedRead
//

import SwiftUI

enum SpineColor {
    static let spineColors: [Color] = [
        Color(red: 0x6B/255.0, green: 0x2D/255.0, blue: 0x26/255.0), // oxblood
        Color(red: 0x2D/255.0, green: 0x4A/255.0, blue: 0x22/255.0), // forest green
        Color(red: 0x3E/255.0, green: 0x27/255.0, blue: 0x23/255.0), // walnut
        Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x2A/255.0), // ochre
        Color(red: 0x5B/255.0, green: 0x2C/255.0, blue: 0x5E/255.0), // plum
        Color(red: 0x8B/255.0, green: 0x4A/255.0, blue: 0x2B/255.0), // burnt sienna
        Color(red: 0x6B/255.0, green: 0x3A/255.0, blue: 0x2A/255.0), // leather brown
        Color(red: 0x4F/255.0, green: 0x5B/255.0, blue: 0x26/255.0), // olive
        Color(red: 0x7A/255.0, green: 0x4A/255.0, blue: 0x2B/255.0), // saddle
        Color(red: 0x31/255.0, green: 0x50/255.0, blue: 0x5E/255.0), // petrol (the one cool spine)
    ]

    static func colorIndex(for title: String) -> Int {
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(hash) % spineColors.count
    }

    static func color(for title: String) -> Color {
        spineColors[colorIndex(for: title)]
    }

    static func color(for title: String, from palette: [Color]) -> Color {
        guard !palette.isEmpty else { return spineColors[colorIndex(for: title)] }
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}
