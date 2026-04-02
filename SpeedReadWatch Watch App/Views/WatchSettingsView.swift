import SwiftUI

struct WatchSettingsView: View {
    var engine: RSVPEngine
    @Environment(\.dismiss) private var dismiss
    @State private var wpmValue: Double = 300

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int(wpmValue))")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            Text("Words Per Minute")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Done") {
                engine.wpm = Int(wpmValue)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
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
