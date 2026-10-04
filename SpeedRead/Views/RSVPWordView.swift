//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View, Animatable {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat
    /// The passages around the word, outermost first; their marks are drawn faintly above it.
    let enclosures: [TextEnclosure]
    /// The words around this one while dragging; hidden while reading.
    var strip: RSVPWordStrip

    init(
        segments: ORPCalculator.WordSegments,
        fontSize: CGFloat = 32,
        enclosures: [TextEnclosure] = [],
        strip: RSVPWordStrip = .hidden
    ) {
        self.segments = segments
        self.fontSize = fontSize
        self.enclosures = enclosures
        self.strip = strip
    }

    /// The strip glides back to the guides and fades when the finger lifts.
    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(strip.offset, strip.opacity) }
        set {
            strip.offset = newValue.first
            strip.opacity = newValue.second
        }
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
                guard strip.opacity > 0 else {
                    context.draw(before, at: CGPoint(x: -focusWidth / 2, y: 0), anchor: .trailing)
                    context.draw(focus, at: .zero, anchor: .center)
                    context.draw(after, at: CGPoint(x: focusWidth / 2, y: 0), anchor: .leading)
                    return
                }
                drawStrip(
                    in: context,
                    current: (before, focus, after),
                    fit: fit,
                    halfWidth: size.width / 2 / max(fit.scale, 0.01)
                )
            }
            .frame(height: fontSize * 1.5)
            guideMark
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.before + segments.focus + segments.after)
    }

    /// The current word and its neighbors on one line, moved by the drag. Every word, the current
    /// one included, is drawn by the same rule, so a word changing hands moves nothing.
    private func drawStrip(
        in context: GraphicsContext,
        current: (before: GraphicsContext.ResolvedText, focus: GraphicsContext.ResolvedText,
                  after: GraphicsContext.ResolvedText),
        fit: RSVPWordFit,
        halfWidth: CGFloat
    ) {
        let proposal = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        let space = context.resolve(segment(" ", color: .rsvpText)).measure(in: proposal).width
        let neighbor = { (word: String) -> (text: GraphicsContext.ResolvedText, word: RSVPWordStripLayout.Word) in
            let parts = ORPCalculator.segments(for: word)
            let measure = { context.resolve(segment($0, color: .rsvpText)).measure(in: proposal).width }
            return (
                context.resolve(segment(word, color: .rsvpText)),
                .init(before: measure(parts.before), focus: measure(parts.focus), after: measure(parts.after))
            )
        }
        let previous = strip.previous.map(neighbor)
        let next = strip.next.map(neighbor)
        let layout = RSVPWordStripLayout(
            current: .init(before: fit.before, focus: fit.focus, after: fit.after),
            previous: previous.map(\.word),
            next: next.map(\.word),
            space: space,
            offset: strip.offset
        )
        let shift = layout.shift
        let neighbors = Array(zip(previous, layout.previousLeadingEdges)) + Array(zip(next, layout.nextLeadingEdges))
        for ((text, word), edge) in neighbors {
            let alpha = layout.alpha(atFocusX: edge + word.focusCenter + shift, halfWidth: halfWidth)
            guard alpha > 0 else { continue }
            var faded = context
            faded.opacity = alpha * strip.opacity * 0.65
            faded.draw(text, at: CGPoint(x: edge + shift, y: 0), anchor: .leading)
        }

        var word = context
        let alpha = layout.alpha(atFocusX: shift, halfWidth: halfWidth)
        word.opacity = 1 - (1 - alpha) * strip.opacity
        let focusWidth = fit.focus
        word.draw(current.before, at: CGPoint(x: shift - focusWidth / 2, y: 0), anchor: .trailing)
        word.draw(current.after, at: CGPoint(x: shift + focusWidth / 2, y: 0), anchor: .leading)
        var plain = word
        plain.opacity *= 0.65
        plain.draw(context.resolve(segment(segments.focus, color: .rsvpText)),
                   at: CGPoint(x: shift, y: 0), anchor: .center)
        word.opacity *= RSVPWordStripLayout.pivotAlpha(offset: strip.offset, stripOpacity: strip.opacity)
        word.draw(current.focus, at: CGPoint(x: shift, y: 0), anchor: .center)
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
