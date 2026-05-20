import SwiftUI

struct WatchSettingsView: View {
    var engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @State private var wpmValue: Double = 300
    @AppStorage("rsvpLastWPM") private var persistedWPM: Int = 300

    var body: some View {
        ZStack {
            Color.walnut.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("\(Int(wpmValue))")
                    .font(.numeric(size: 36))
                    .foregroundStyle(Color.agedGold)

                Text("Words Per Minute")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.parchment.opacity(0.6))

                Button("Done") {
                    let newWPM = Int(wpmValue)
                    engine.wpm = newWPM
                    persistedWPM = newWPM
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crimsonSoft)
            }
        }
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
            let snapped = (newValue / 10).rounded() * 10
            if snapped != newValue {
                wpmValue = snapped
            }
        }
        .onAppear {
            wpmValue = (Double(engine.wpm) / 10).rounded() * 10
        }
    }
}
