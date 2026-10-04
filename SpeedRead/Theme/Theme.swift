//  Theme.swift
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension Color {
    // MARK: - Core Palette
    static let walnut = Color(red: 0x3E / 255.0, green: 0x27 / 255.0, blue: 0x23 / 255.0)
    static let walnutLight = Color(red: 0x5D / 255.0, green: 0x40 / 255.0, blue: 0x37 / 255.0)
    static let parchment = Color(red: 0xFF / 255.0, green: 0xF8 / 255.0, blue: 0xE7 / 255.0)
    static let parchmentDark = Color(red: 0xF0 / 255.0, green: 0xE6 / 255.0, blue: 0xD0 / 255.0)
    static let inkBlack = Color(red: 0x1C / 255.0, green: 0x14 / 255.0, blue: 0x10 / 255.0)
    static let agedGold = Color(red: 0xC8 / 255.0, green: 0xA9 / 255.0, blue: 0x51 / 255.0)
    static let lamplight = Color(red: 0xFF / 255.0, green: 0xE0 / 255.0, blue: 0xA0 / 255.0)

    // MARK: - RSVP Mode
    static let rsvpBackground = Color(red: 0x1A / 255.0, green: 0x12 / 255.0, blue: 0x10 / 255.0)
    static let rsvpText = Color(red: 0xF5 / 255.0, green: 0xED / 255.0, blue: 0xE0 / 255.0)

    // MARK: - Semantic app-chrome tokens (light/dark adaptive)

    /// Resolves per appearance. watchOS is always dark, so it takes the dark value.
    /// `nonisolated` is load-bearing: UIDynamicProviderColor invokes the closure on
    /// whatever thread SwiftUI's AttributeGraph is updating, and a MainActor-isolated
    /// closure SIGTRAPs there under Swift 6 executor checks.
    nonisolated static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        dark
        #endif
    }

    /// Sheet/chrome background: parchment in light, warm near-black in dark.
    static let appSurface = adaptive(light: .parchment, dark: .rsvpBackground)
    /// List rows and cards over `appSurface`.
    static let appSurfaceRaised = adaptive(
        light: .parchmentDark,
        dark: Color(red: 0x25 / 255.0, green: 0x1A / 255.0, blue: 0x14 / 255.0)
    )
    /// Primary text.
    static let appInk = adaptive(light: .inkBlack, dark: .rsvpText)
    /// Secondary text; stays above 4.5:1 on both surfaces.
    static let appInkSecondary = adaptive(
        light: .walnutLight,
        dark: Color(red: 0xB9 / 255.0, green: 0xA9 / 255.0, blue: 0x8F / 255.0)
    )
    /// Buttons, links, tint: saddle brown in light, aged gold in dark.
    static let appAccent = adaptive(
        light: Color(red: 0x7A / 255.0, green: 0x4A / 255.0, blue: 0x2B / 255.0),
        dark: Color(red: 0xD9 / 255.0, green: 0xB9 / 255.0, blue: 0x68 / 255.0)
    )
    /// Text drawn on an `appAccent` fill.
    static let appOnAccent = adaptive(light: .parchment, dark: .rsvpBackground)
    /// Gold that stays readable as text; `agedGold` itself is fill/ornament only on light surfaces.
    static let appGoldText = adaptive(
        light: Color(red: 0x8A / 255.0, green: 0x6A / 255.0, blue: 0x1F / 255.0),
        dark: Color(red: 0xD9 / 255.0, green: 0xB9 / 255.0, blue: 0x68 / 255.0)
    )
    /// The one red in the app: the RSVP ORP pivot letter, its guide ticks, and the
    /// reader's last-read word. Never an accent, never decoration.
    static let pivot = adaptive(
        light: Color(red: 0xB3 / 255.0, green: 0x26 / 255.0, blue: 0x1E / 255.0),
        dark: Color(red: 0xE2 / 255.0, green: 0x57 / 255.0, blue: 0x4C / 255.0)
    )
    /// Validation and destructive text — a deeper brick than `pivot`, disjoint surfaces.
    static let appError = adaptive(
        light: Color(red: 0xA2 / 255.0, green: 0x3B / 255.0, blue: 0x2A / 255.0),
        dark: Color(red: 0xE8 / 255.0, green: 0x80 / 255.0, blue: 0x6F / 255.0)
    )
    /// Success/confirmation text — muted moss, replaces system green.
    static let appSuccess = adaptive(
        light: Color(red: 0x4F / 255.0, green: 0x6B / 255.0, blue: 0x3A / 255.0),
        dark: Color(red: 0x9D / 255.0, green: 0xBE / 255.0, blue: 0x7E / 255.0)
    )
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
