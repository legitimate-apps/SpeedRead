import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch RSVP accessibility")
@MainActor
struct WatchRSVPAccessibilityTests {
    @Test func playbackControlHasStableSemanticsInBothStates() {
        #expect(WatchRSVPPlaybackControl.accessibilityIdentifier == "rsvp-playback-toggle")
        #expect(WatchRSVPPlaybackControl.accessibilityLabel(isPlaying: false) == "Play")
        #expect(WatchRSVPPlaybackControl.accessibilityLabel(isPlaying: true) == "Pause")
    }

    @Test func rsvpSurfaceStructurallyContainsThePlaybackButton() {
        let engine = RSVPEngine()
        engine.load(words: ["one", "two"], startingAt: 0)
        let surface = WatchRSVPSurface(
            engine: engine,
            onTogglePlayback: {},
            onOpenSettings: {}
        )

        let bodyType = String(reflecting: type(of: surface.body))

        #expect(bodyType.contains("WatchRSVPPlaybackControl"))
    }
}
