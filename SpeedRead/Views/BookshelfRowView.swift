//  BookshelfRowView.swift
import SwiftUI

struct BookshelfRowView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Books sitting on the shelf
            HStack(alignment: .bottom, spacing: 8) {
                content
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 0)

            // Shelf plank
            shelfPlank
        }
    }

    private var shelfPlank: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.walnutLight,
                            Color.walnut,
                            Color.walnut.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 12)

            // Subtle edge highlight
            Rectangle()
                .fill(Color.lamplight.opacity(0.15))
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
}
