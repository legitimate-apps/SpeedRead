//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat
    /// The passages around the word, outermost first; their marks are drawn faintly above it.
    let enclosures: [TextEnclosure]

    init(segments: ORPCalculator.WordSegments, fontSize: CGFloat = 32, enclosures: [TextEnclosure] = []) {
        self.segments = segments
        self.fontSize = fontSize
        self.enclosures = enclosures
    }

    var body: some View {
        VStack(spacing: 2) {
            guideMark
                .overlay { enclosureMarks }
            Canvas { context, size in
                let before = context.resolve(segment(segments.before, color: .rsvpText.opacity(0.65)))
                let focus = context.resolve(segment(segments.focus, color: .pivot))
                let after = context.resolve(segment(segments.after, color: .rsvpText.opacity(0.65)))
                let proposal = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
                let focusWidth = focus.measure(in: proposal).width
                let fit = RSVPWordFit(
                    before: before.measure(in: proposal).width,
                    focus: focusWidth,
                    after: after.measure(in: proposal).width,
                    availableWidth: size.width
                )
                context.translateBy(x: fit.focusCenter, y: size.height / 2)
                context.scaleBy(x: fit.scale, y: fit.scale)
                context.draw(before, at: CGPoint(x: -focusWidth / 2, y: 0), anchor: .trailing)
                context.draw(focus, at: .zero, anchor: .center)
                context.draw(after, at: CGPoint(x: focusWidth / 2, y: 0), anchor: .leading)
            }
            .frame(height: fontSize * 1.5)
            guideMark
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.before + segments.focus + segments.after)
    }

    /// The marks of the passages around the word, either side of the upper guide: outermost
    /// pair outside, faint and small, so the eye registers "inside quotes" without reading them.
    /// The font is monospaced and every pair is the same width, so the guide stays centered.
    @ViewBuilder
    private var enclosureMarks: some View {
        let shown = enclosures.suffix(3)
        if !shown.isEmpty {
            HStack(spacing: fontSize * 0.7) {
                mark(shown.map(\.opener).joined(separator: " "))
                mark(shown.reversed().map(\.closer).joined(separator: " "))
            }
            .fixedSize()
            .accessibilityHidden(true)
        }
    }

    private func mark(_ string: String) -> Text {
        Text(string).font(.system(size: fontSize * 0.5, weight: .semibold, design: .monospaced))
            .foregroundColor(.rsvpText.opacity(0.5))
    }

    private func segment(_ string: String, color: Color) -> Text {
        Text(string).font(.rsvpWord(size: fontSize)).foregroundColor(color)
    }

    private var guideMark: some View {
        Rectangle()
            .fill(Color.pivot)
            .frame(width: 2, height: 8)
            .accessibilityHidden(true)
    }
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "electroencephalographically"))
        .background(Color.rsvpBackground)
}
