//  BookshelfRowView.swift
import SwiftUI

struct BookshelfRowView<Content: View>: View {
    let content: Content

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let metrics = LibraryLayoutMetrics(
            isRegularWidth: horizontalSizeClass == .regular,
            containerWidth: 0
        )

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if metrics.isRegularWidth {
                    shelfBay(metrics: metrics)
                }

                EqualShelfSlotLayout(metrics: metrics) {
                    content
                }
                .padding(.horizontal, metrics.horizontalInset + metrics.sideRailWidth)
            }

            shelfPlank(height: metrics.shelfPlankHeight)
        }
    }

    private func shelfBay(metrics: LibraryLayoutMetrics) -> some View {
        let theme = themeManager.currentTheme

        return ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.shelfColor.opacity(0.20),
                            theme.backgroundColor.opacity(0.78),
                            theme.shelfColor.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 24)
                .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 0) {
                sideRail(theme: theme, width: metrics.sideRailWidth)
                Spacer(minLength: 0)
                sideRail(theme: theme, width: metrics.sideRailWidth)
            }
        }
        .frame(height: metrics.maximumSpineHeight)
        .overlay {
            Rectangle()
                .strokeBorder(theme.shelfColor.opacity(0.22), lineWidth: 1)
        }
    }

    private func sideRail(theme: ShelfTheme, width: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        theme.shelfColor.opacity(0.78),
                        theme.shelfColor,
                        theme.shelfColor.opacity(0.72)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width)
            .shadow(color: .black.opacity(0.18), radius: 3, x: width > 0 ? 2 : 0)
    }

    private func shelfPlank(height: CGFloat) -> some View {
        let theme = themeManager.currentTheme

        return ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.shelfColor.opacity(0.8),
                            theme.shelfColor,
                            theme.shelfColor.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: height)

            Rectangle()
                .fill(theme.shelfHighlightColor.opacity(0.15))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .shadow(color: .black.opacity(0.34), radius: 4, y: 3)
    }
}

#Preview {
    ScrollView {
        BookshelfRowView {
            BookSpineView(title: "Alice", author: "Carroll", progress: 0.5, wordCount: 27000)
            BookSpineView(title: "Kafka", author: "Kafka", progress: 0, wordCount: 15000)
        }
    }
    .background(Color.parchment)
    .environment(ThemeManager())
}
