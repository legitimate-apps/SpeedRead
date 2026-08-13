//  BookSpineView.swift
import SwiftUI

struct BookSpineView: View {
    let title: String
    let author: String
    let progress: Double
    let wordCount: Int

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var metrics: LibraryLayoutMetrics {
        LibraryLayoutMetrics(
            isRegularWidth: horizontalSizeClass == .regular,
            containerWidth: 0
        )
    }

    private var spineHeight: CGFloat {
        let base = metrics.minimumSpineHeight
        let range = metrics.maximumSpineHeight - metrics.minimumSpineHeight
        let extra = min(CGFloat(wordCount) / 50_000.0, 1.0) * range
        return base + extra
    }

    private var spineColor: Color {
        SpineColor.color(for: title, from: themeManager.currentTheme.spineColors)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        ZStack(alignment: .bottom) {
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

            VStack(spacing: 4) {
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: metrics.titleFontSize, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.spineTextColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text(author)
                    .font(.system(size: metrics.authorFontSize, weight: .regular, design: theme.fontDesign))
                    .foregroundStyle(theme.spineTextColor.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(width: metrics.spineWidth, height: spineHeight)
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
    .environment(ThemeManager())
}
