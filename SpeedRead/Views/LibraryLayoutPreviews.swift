#if DEBUG
import SwiftUI

private struct LibraryShelfPreview: View {
    let bookCount: Int
    let regularWidth: Bool

    private let titles = [
        "Alice in Wonderland", "Metamorphosis", "A Christmas Carol",
        "The Yellow Wallpaper", "Frankenstein", "Pride and Prejudice"
    ]

    var body: some View {
        GeometryReader { geometry in
            let metrics = LibraryLayoutMetrics(
                isRegularWidth: regularWidth,
                containerWidth: geometry.size.width
            )
            let shelves = metrics.shelves(for: Array(0..<bookCount))
            let visibleCount = max(
                shelves.count,
                metrics.minimumVisibleShelfCount(viewportHeight: geometry.size.height)
            )

            ScrollView {
                LazyVStack(spacing: metrics.shelfSpacing) {
                    ForEach(0..<visibleCount, id: \.self) { shelfIndex in
                        BookshelfRowView {
                            if shelfIndex < shelves.count {
                                ForEach(shelves[shelfIndex], id: \.self) { index in
                                    BookSpineView(
                                        title: titles[index % titles.count],
                                        author: "Preview Author",
                                        progress: index.isMultiple(of: 3) ? 0.45 : 0,
                                        wordCount: 12_000 + (index * 4_000)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
        .background(Color.parchment)
        .environment(ThemeManager())
        .environment(\.horizontalSizeClass, regularWidth ? .regular : .compact)
    }
}

#Preview("Compact phone — unchanged") {
    LibraryShelfPreview(bookCount: 4, regularWidth: false)
        .frame(width: 393, height: 852)
}

#Preview("iPad portrait") {
    LibraryShelfPreview(bookCount: 12, regularWidth: true)
        .frame(width: 1_024, height: 1_366)
}

#Preview("iPad landscape") {
    LibraryShelfPreview(bookCount: 14, regularWidth: true)
        .frame(width: 1_366, height: 1_024)
}

#Preview("iPad sparse — four books") {
    LibraryShelfPreview(bookCount: 4, regularWidth: true)
        .frame(width: 1_024, height: 1_366)
}

#Preview("iPad overflow — second shelf") {
    LibraryShelfPreview(bookCount: 13, regularWidth: true)
        .frame(width: 1_024, height: 1_366)
}
#endif
