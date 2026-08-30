import SwiftUI

struct WatchSettingsView: View {
    var engine: RSVPEngine
    let onRestoreReadingPosition: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onRestoreReadingPosition()
                    dismiss()
                } label: {
                    Label("Back to where I was reading", systemImage: "arrow.uturn.backward")
                }

                NavigationLink {
                    WatchSpeedSettingsView(engine: engine)
                } label: {
                    LabeledContent("Speed", value: "\(engine.wpm) WPM")
                }
            }
            .navigationTitle("Reading Settings")
            .accessibilityIdentifier("watch-reading-settings-list")
        }
    }
}

private struct WatchSpeedSettingsView: View {
    var engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @State private var wpmValue: Double = 300
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = 300

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int(wpmValue))")
                .font(.numeric(size: 36))
                .foregroundStyle(Color.agedGold)

            Text("Words Per Minute")
                .font(.system(size: 11))
                .foregroundStyle(Color.parchment.opacity(0.6))

            Button("Done") {
                persistedWPM = WatchSettingsLogic.apply(wpmValue, to: engine)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crimsonSoft)
        }
        .containerBackground(Color.walnut.gradient, for: .navigation)
        .focusable()
        .digitalCrownRotation(
            $wpmValue,
            from: 100,
            through: 1000,
            by: 10,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: wpmValue) { _, newValue in
            let snapped = Double(WatchSettingsLogic.snappedWPM(newValue))
            if snapped != newValue {
                wpmValue = snapped
            }
        }
        .onAppear {
            wpmValue = Double(WatchSettingsLogic.snappedWPM(Double(engine.wpm)))
        }
    }
}
