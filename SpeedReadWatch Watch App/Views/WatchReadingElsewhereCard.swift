import SwiftUI

/// Covers the RSVP surface while the phone reads this book. The word underneath follows the
/// phone; "Read here" takes the book over, and the phone yields when it hears the watch play.
struct WatchReadingElsewhereCard: View {
    let presence: RemotePresence
    let book: WatchBook
    let onReadHere: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.agedGold)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
            Text(LiveHandoffLogic.cardTitle(readingOn: HandoffDevice.current.counterpart))
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color.rsvpText)
                .multilineTextAlignment(.center)
            Text(LiveHandoffLogic.cardDetail(presence: presence, wordCount: book.wordCount,
                                             chapters: book.chapters))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.rsvpText.opacity(0.7))
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: 4)
            Button(action: onReadHere) {
                Text("Read here")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(Color.rsvpBackground)
                    .background(Color.agedGold, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch-reading-elsewhere-read-here")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque: on a 46 mm screen a translucent card lets the RSVP word bleed through its text.
        .background(Color.rsvpBackground.ignoresSafeArea())
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch-reading-elsewhere-card")
    }
}
