//  RSVPWordView.swift
import SwiftUI

struct RSVPWordView: View {
    let segments: ORPCalculator.WordSegments
    let fontSize: CGFloat

    init(segments: ORPCalculator.WordSegments, fontSize: CGFloat = 32) {
        self.segments = segments
        self.fontSize = fontSize
    }

    private var font: Font {
        .rsvpWord(size: fontSize)
    }

    private var charWidth: CGFloat {
        fontSize * 0.6
    }

    private let maxSideChars = 12

    var body: some View {
        VStack(spacing: 2) {
            guideMark

            HStack(spacing: 0) {
                Text(segments.before)
                    .font(font)
                    .foregroundStyle(Color.rsvpText.opacity(0.5))
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .trailing)

                Text(segments.focus)
                    .font(font)
                    .foregroundStyle(Color.crimson)
                    .frame(width: charWidth, alignment: .center)

                Text(segments.after)
                    .font(font)
                    .foregroundStyle(Color.rsvpText.opacity(0.5))
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .leading)
            }

            guideMark
        }
        .padding(.horizontal)
    }

    private var guideMark: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
            Rectangle()
                .fill(Color.crimson)
                .frame(width: 2, height: 8)
                .frame(width: charWidth)
            Spacer()
                .frame(width: charWidth * CGFloat(maxSideChars))
        }
        .padding(.horizontal)
    }
}

#Preview("Simple word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "reading"))
        .background(Color.rsvpBackground)
}

#Preview("Short word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "Hi"))
        .background(Color.rsvpBackground)
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "presentation"))
        .background(Color.rsvpBackground)
}
