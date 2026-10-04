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
        /// A slow drag moves a word per this many points, so a word at a time can be picked out;
        /// faster drags accelerate down to `basePointsPerWord² / maximumVelocityMultiplier`
        /// (about 1.3 points a word), the speed scrubbing had before the strip was drawn.
        static let basePointsPerWord: CGFloat = 14
        static let velocityPointsPerSecond: CGFloat = 300
        static let maximumVelocityMultiplier: CGFloat = 150
        static let hapticWordInterval = 10
        static let scrubActivationDistance: CGFloat = 5
        static let controlPanelHeight: CGFloat = 160
        static let controlPanelBottomPadding: CGFloat = 20
        static let feedbackFlashDuration = Duration.milliseconds(300)
        static let feedbackFadeDuration = 0.2
    }
}
