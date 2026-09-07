import Foundation

/// Fits measured text around a stationary, centered ORP pivot.
///
/// This type deliberately lives outside `RSVPWordView.swift`: attributable coverage is
/// measured per source file, so testable decisions beside SwiftUI markup make both look untested.
/// Segment widths are nonnegative intrinsic measurements, before scaling.
nonisolated struct RSVPWordFit {
    let before: CGFloat
    let focus: CGFloat
    let after: CGFloat
    let availableWidth: CGFloat

    var scale: CGFloat {
        guard availableWidth > 0 else { return 0 }
        let requiredWidth = 2 * max(before, after) + focus
        return requiredWidth > 0 ? min(1, availableWidth / requiredWidth) : 1
    }

    var focusCenter: CGFloat { max(0, availableWidth) / 2 }
    var leadingEdge: CGFloat { focusCenter - (focus / 2 + before) * scale }
    var trailingEdge: CGFloat { focusCenter + (focus / 2 + after) * scale }
}
