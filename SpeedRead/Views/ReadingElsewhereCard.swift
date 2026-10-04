import SwiftUI

/// Shown over a book while the watch reads it. The only way forward is "Read here", which takes
/// the book over; the watch yields when it hears this device play.
struct ReadingElsewhereCard: View {
    let presence: RemotePresence
    let wordCount: Int
    let chapters: [ChapterMark]
    let background: Color
    let foreground: Color
    let accent: Color
    let onAccent: Color
    let onReadHere: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accent)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LiveHandoffLogic.cardTitle(readingOn: HandoffDevice.current.counterpart))
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(foreground)
                    Text(LiveHandoffLogic.cardDetail(presence: presence, wordCount: wordCount, chapters: chapters))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(foreground.opacity(0.7))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Button(action: onReadHere) {
                Text("Read here")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(onAccent)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reading-elsewhere-read-here")
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(foreground.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reading-elsewhere-card")
    }
}
