//  BookSpineView.swift
import SwiftUI

struct BookSpineView: View {
    let title: String
    let author: String
    let progress: Double
    let wordCount: Int

    // Spine height varies by word count: 120-180pt
    private var spineHeight: CGFloat {
        let base: CGFloat = 120
        let extra = min(CGFloat(wordCount) / 50_000.0, 1.0) * 60
        return base + extra
    }

    private var spineColor: Color {
        SpineColor.color(for: title)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Spine body
            RoundedRectangle(cornerRadius: 4)
                .fill(spineColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.15))
                        .frame(width: 2)
                        .padding(.vertical, 8),
                    alignment: .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)

            // Title and author text
            VStack(spacing: 4) {
                Text(title)
                    .font(.displayFont(size: 11, weight: .semibold))
                    .foregroundStyle(Color.parchment)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(author)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Color.parchment.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)

            // Progress indicator — gold line at bottom
            if progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.agedGold)
                        .frame(width: geo.size.width, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(0.8)
                }
            }
        }
        .frame(width: 60, height: spineHeight)
    }
}

#Preview {
    HStack(spacing: 8) {
        BookSpineView(title: "Alice in Wonderland", author: "Lewis Carroll", progress: 0.4, wordCount: 27000)
        BookSpineView(title: "The Metamorphosis", author: "Franz Kafka", progress: 0, wordCount: 15000)
        BookSpineView(title: "A Christmas Carol", author: "Charles Dickens", progress: 0.8, wordCount: 30000)
    }
    .padding()
    .background(Color.walnut)
}
