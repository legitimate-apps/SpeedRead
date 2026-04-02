//
//  SpineColor.swift
//  SpeedRead
//

import SwiftUI

enum SpineColor {
    static let spineColors: [Color] = [
        Color(red: 0x00/255.0, green: 0x5F/255.0, blue: 0x73/255.0), // deep teal
        Color(red: 0x7B/255.0, green: 0x2D/255.0, blue: 0x26/255.0), // burgundy
        Color(red: 0x2D/255.0, green: 0x4A/255.0, blue: 0x22/255.0), // forest green
        Color(red: 0x1B/255.0, green: 0x2A/255.0, blue: 0x4A/255.0), // navy
        Color(red: 0x8B/255.0, green: 0x4A/255.0, blue: 0x2B/255.0), // burnt sienna
        Color(red: 0x5B/255.0, green: 0x2C/255.0, blue: 0x5E/255.0), // plum
        Color(red: 0x4A/255.0, green: 0x5A/255.0, blue: 0x6A/255.0), // slate blue
        Color(red: 0x8B/255.0, green: 0x73/255.0, blue: 0x2A/255.0), // ochre
        Color(red: 0x3E/255.0, green: 0x27/255.0, blue: 0x23/255.0), // walnut
        Color(red: 0x6B/255.0, green: 0x3A/255.0, blue: 0x2A/255.0), // leather brown
    ]

    static func colorIndex(for title: String) -> Int {
        let hash = title.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(hash) % spineColors.count
    }

    static func color(for title: String) -> Color {
        spineColors[colorIndex(for: title)]
    }
}
