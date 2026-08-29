import SwiftUI

struct RSVPPlaybackControl: View {
    static let accessibilityIdentifier = "rsvp-playback-toggle"

    let isPlaying: Bool
    let action: () -> Void

    static func accessibilityLabel(isPlaying: Bool) -> String {
        isPlaying ? "Pause" : "Play"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
        }
        .accessibilityLabel(Self.accessibilityLabel(isPlaying: isPlaying))
        .accessibilityHint(isPlaying ? "Pauses RSVP reading" : "Starts RSVP reading")
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }
}
