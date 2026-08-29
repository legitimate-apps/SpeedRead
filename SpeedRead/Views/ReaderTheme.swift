import SwiftUI

enum ReaderThemeMode: String, CaseIterable {
    case parchment
    case sepia
    case night

    var palette: ReaderPalette {
        switch self {
        case .parchment:
            ReaderPalette(
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
            ReaderPalette(
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
            ReaderPalette(
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
}

struct ReaderPalette {
    let background: Color
    let titleText: Color
    let bodyText: Color
    let headerText: Color
    let accent: Color
    let barBackground: Color
    let barText: Color
    let toolbarColorScheme: ColorScheme
}
