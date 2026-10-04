import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchRSVPPlaybackControl: View {
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
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(isPlaying: isPlaying))
        .accessibilityHint(isPlaying ? "Pauses RSVP reading" : "Starts RSVP reading")
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }
}

struct WatchRSVPSurface: View {
    /// The one width the controls row must never exceed.
    static var screenWidth: CGFloat {
        #if os(watchOS)
        WKInterfaceDevice.current().screenBounds.width
        #else
        200
        #endif
    }

    var engine: RSVPEngine
    let onTogglePlayback: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Color.rsvpBackground
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTogglePlayback)
                .onLongPressGesture(perform: onOpenSettings)

            if engine.state == .playing {
                RSVPWordView(segments: engine.currentSegments, fontSize: 20, enclosures: engine.currentEnclosures)
                    .frame(width: Self.screenWidth)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(engine.currentWord)
                    .accessibilityValue("\(engine.currentIndex)")
                    .accessibilityIdentifier("watch-rsvp-position")

                VStack {
                    Spacer()
                    WatchRSVPPlaybackControl(isPlaying: true, action: onTogglePlayback)
                        .font(.system(size: 30))
                        .foregroundStyle(Color.agedGold)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.bottom, 2)
                }
            } else {
                VStack(spacing: 0) {
                    // The sheet supplies the close control; the surface supplies only settings.
                    HStack {
                        Spacer()

                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.rsvpText)
                                .frame(width: 36, height: 36)
                                .background(Color.rsvpText.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    Spacer()

                    RSVPWordView(segments: engine.currentSegments, fontSize: 18, enclosures: engine.currentEnclosures)
                        .frame(width: Self.screenWidth)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(engine.currentWord)
                        .accessibilityValue("\(engine.currentIndex)")
                        .accessibilityIdentifier("watch-rsvp-position")

                    Spacer()

                    WatchRSVPPlaybackControl(isPlaying: false, action: onTogglePlayback)
                        .font(.system(size: 44))
                        .foregroundStyle(Color.agedGold)
                        .frame(minWidth: 44, minHeight: 44)

                    Text("\(engine.wpm) WPM")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.agedGold)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
