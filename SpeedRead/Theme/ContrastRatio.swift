//
//  ContrastRatio.swift
//  SpeedRead
//

import Foundation
import CoreGraphics

/// WCAG 2.x relative-luminance contrast over sRGB channels.
///
/// Pure math with no SwiftUI dependency so palette tokens can be gated on the 4.5:1 text /
/// 3:1 non-text floor from tests. Semi-transparent foregrounds are composited over the
/// (assumed opaque) background before measuring, because that is what the eye sees.
nonisolated enum ContrastRatio {
    nonisolated struct RGBA: Equatable, Sendable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    /// Contrast ratio between two colors, 1...21. A translucent `foreground` is first
    /// composited over `background`; `background` itself is treated as opaque.
    static func ratio(foreground: RGBA, background: RGBA) -> CGFloat {
        let fg = foreground.alpha >= 1 ? foreground : composited(foreground: foreground, over: background)
        let bright = max(luminance(fg), luminance(background))
        let dark = min(luminance(fg), luminance(background))
        return (bright + 0.05) / (dark + 0.05)
    }

    static func luminance(_ color: RGBA) -> CGFloat {
        0.2126 * linearized(color.red) + 0.7152 * linearized(color.green) + 0.0722 * linearized(color.blue)
    }

    static func composited(foreground: RGBA, over background: RGBA) -> RGBA {
        let a = foreground.alpha
        return RGBA(
            red: foreground.red * a + background.red * (1 - a),
            green: foreground.green * a + background.green * (1 - a),
            blue: foreground.blue * a + background.blue * (1 - a),
            alpha: 1
        )
    }

    private static func linearized(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
