//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat

    init(segments: ORPCalculator.WordSegments, fontSize: CGFloat = 32) {
        self.segments = segments
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(spacing: 2) {
            guideMark
            Canvas { context, size in
                let before = context.resolve(segment(segments.before, color: .rsvpText.opacity(0.5)))
                let focus = context.resolve(segment(segments.focus, color: .crimson))
                let after = context.resolve(segment(segments.after, color: .rsvpText.opacity(0.5)))
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

    private func segment(_ string: String, color: Color) -> Text {
        Text(string).font(.rsvpWord(size: fontSize)).foregroundColor(color)
    }

    private var guideMark: some View {
        Rectangle()
            .fill(Color.crimson)
            .frame(width: 2, height: 8)
            .accessibilityHidden(true)
    }
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "electroencephalographically"))
        .background(Color.rsvpBackground)
}
