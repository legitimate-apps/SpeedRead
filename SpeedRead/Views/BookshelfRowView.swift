//  BookshelfRowView.swift
import SwiftUI

struct BookshelfRowView<Content: View>: View {
    let content: Content

    @Environment(ThemeManager.self) private var themeManager

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                content
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 0)

            shelfPlank
        }
    }

    private var shelfPlank: some View {
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
                .frame(height: 12)

            Rectangle()
                .fill(theme.shelfHighlightColor.opacity(0.15))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 12)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
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
