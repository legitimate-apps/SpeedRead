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
                accent: Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x2B / 255),
                onAccent: Color.parchment,
                pivot: Color(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x1E / 255),
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
                accent: Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x2B / 255),
                onAccent: Color.parchment,
                pivot: Color(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x1E / 255),
                barBackground: Color(red: 0xF1 / 255, green: 0xE3 / 255, blue: 0xC2 / 255).opacity(0.94),
                barText: Color(red: 0x42 / 255, green: 0x2A / 255, blue: 0x12 / 255).opacity(0.8),
                toolbarColorScheme: .light
            )
        case .night:
            ReaderPalette(
                background: Color(red: 0x17 / 255, green: 0x11 / 255, blue: 0x0E / 255),
                titleText: Color(red: 0xF1 / 255, green: 0xEC / 255, blue: 0xDD / 255),
                bodyText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.92),
                headerText: Color(red: 0xE7 / 255, green: 0xE2 / 255, blue: 0xD2 / 255).opacity(0.85),
                accent: Color(red: 0xD9 / 255, green: 0xB9 / 255, blue: 0x68 / 255),
                onAccent: Color(red: 0x1A / 255, green: 0x12 / 255, blue: 0x10 / 255),
                pivot: Color(red: 0xE2 / 255, green: 0x57 / 255, blue: 0x4C / 255),
                barBackground: Color(red: 0x1F / 255, green: 0x18 / 255, blue: 0x14 / 255).opacity(0.94),
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
    /// Filled-button color on this page (RSVP pill, offer-banner actions): saddle on the
    /// light pages, aged gold on night.
    let accent: Color
    /// Text drawn on an `accent` fill.
    let onAccent: Color
    /// The last-read word marker — the only red on the page, shared language with the
    /// RSVP ORP pivot.
    let pivot: Color
    let barBackground: Color
    let barText: Color
    let toolbarColorScheme: ColorScheme

    /// List-row fill over `background` — a whisper of the page's own ink.
    var rowFill: Color { bodyText.opacity(0.08) }
}
