import CoreGraphics
import Foundation

enum ReaderConfig {
    enum Classic {
        static let defaultFontSize = 18.0
        static let fontSizeRange = 12.0...34.0
        static let fontSizeStep = 2.0
        static let defaultLineSpacing = 6.0
        static let lineSpacingRange = 2.0...18.0
        static let lineSpacingStep = 1.0
        static let phoneHorizontalPadding: CGFloat = 22
        static let padHorizontalPadding: CGFloat = 64
        static let scrollAnimationDuration = 0.35
        static let wordFlashDuration = Duration.milliseconds(600)
        static let rsvpTransitionDelay = Duration.milliseconds(200)
        static let bottomContentInset: CGFloat = 140
    }

    enum RSVP {
        static let defaultWPM = 300
        static let minimumEstimateWPM = 60
        static let wpmStep = 25
        /// A drag moves the line of words exactly with the finger. When it lifts, the line carries
        /// on as far as the finger would have gone in `flingProjection` seconds at the speed it
        /// left at, and lands on the nearest word; slower than `flingMinimumVelocity` (points a
        /// second) it settles onto the word on the guides instead.
        nonisolated static let flingProjection: TimeInterval = 0.25
        nonisolated static let flingMinimumVelocity: CGFloat = 300
        nonisolated static let flingDurationRange: ClosedRange<TimeInterval> = 0.25...1.1
        /// A runaway bound on how many words one fling may cross.
        nonisolated static let flingMaximumWords = 60
        nonisolated static let settleDuration: TimeInterval = 0.2
        /// After landing, the words either side fade out over this long.
        nonisolated static let stripFadeDuration: TimeInterval = 0.18
        /// The finger's speed at release is measured over its last `releaseVelocityWindow` seconds,
        /// never over less than a frame, and capped: one late touch event cannot fling the line.
        nonisolated static let releaseVelocityWindow: TimeInterval = 0.05
        nonisolated static let releaseVelocityMinimumSpan: TimeInterval = 1.0 / 60
        nonisolated static let flingMaximumVelocity: CGFloat = 4_000
        /// The most the line gives, in points, when dragged past either end of the book.
        nonisolated static let edgeStretchLimit: CGFloat = 60
        static let scrubActivationDistance: CGFloat = 5
        static let controlPanelHeight: CGFloat = 160
        static let controlPanelBottomPadding: CGFloat = 20
        static let feedbackFlashDuration = Duration.milliseconds(300)
        static let feedbackFadeDuration = 0.2
    }
}
