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
        .system(size: fontSize, weight: .bold, design: .monospaced)
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
                    .foregroundStyle(.secondary)
                    .frame(width: charWidth * CGFloat(maxSideChars), alignment: .trailing)

                Text(segments.focus)
                    .font(font)
                    .foregroundStyle(.red)
                    .frame(width: charWidth, alignment: .center)

                Text(segments.after)
                    .font(font)
                    .foregroundStyle(.secondary)
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
                .fill(.red)
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
        .preferredColorScheme(.dark)
}

#Preview("Short word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "Hi"))
        .preferredColorScheme(.dark)
}

#Preview("Long word") {
    RSVPWordView(segments: ORPCalculator.segments(for: "presentation"))
        .preferredColorScheme(.dark)
}
