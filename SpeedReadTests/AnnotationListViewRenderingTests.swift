import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

/// Characterization using the LibraryViewRenderingTests window-hosting pattern.
/// Pixel samples retain their positions so moving or changing row text is observable.
@Suite("Annotation list view rendering", .serialized)
@MainActor
struct AnnotationListViewRenderingTests {
    @Test func bookmarksRenderEmptySortedUpdatedAndDeletedStates() async throws {
        let fixture = try Fixture()
        let host = UIHostingController(rootView: BookmarkListView(book: fixture.book, engine: fixture.engine)
            .modelContainer(fixture.container))
        let window = try hostInWindow(host)
        defer { window.isHidden = true }
        let empty = try await signature(in: host.view)
        #expect(AnnotationListLogic.ordered(fixture.book.bookmarks).isEmpty)
        #expect(Set(empty).count > 8)

        let later = Bookmark(wordIndex: 40, previewText: "Later bookmark passage")
        let first = Bookmark(wordIndex: 0, previewText: "Opening bookmark passage")
        let tied = Bookmark(wordIndex: 0, previewText: "Second bookmark at the opening")
        first.createdAt = Date(timeIntervalSince1970: 1_000)
        tied.createdAt = Date(timeIntervalSince1970: 2_000)
        later.createdAt = Date(timeIntervalSince1970: 3_000)
        fixture.book.bookmarks = [later, tied, first]
        try fixture.container.mainContext.save()
        let populated = try await signature(in: host.view)
        let ordered = AnnotationListLogic.ordered(fixture.book.bookmarks)
        #expect(ordered.map(\.id) == [first.id, tied.id, later.id])
        #expect(ordered.map { AnnotationListLogic.positionLabel(wordIndex: $0.wordIndex) }
            == ["Word 1", "Word 1", "Word 41"])
        #expect(populated != empty)

        first.previewText = "CHANGED: a visibly different saved passage"
        let updated = try await signature(in: host.view)
        let previewChanged = updated != populated
        #expect(previewChanged, "Changing bookmark preview text must change the rendered row")
        #expect(ordered.first?.previewText == "CHANGED: a visibly different saved passage")

        fixture.book.bookmarks = [first, later, tied]
        let reordered = try await signature(in: host.view)
        #expect(reordered == updated, "Relationship insertion order must not change display order")

        let doomed = AnnotationListLogic.bookmarksToDelete(at: IndexSet([0, 1]), from: ordered)
        #expect(doomed.map(\.id) == [first.id, tied.id])
        for bookmark in doomed { fixture.container.mainContext.delete(bookmark) }
        try fixture.container.mainContext.save()
        let singleton = try await signature(in: host.view)
        #expect(fixture.book.bookmarks.map(\.id) == [later.id])
        #expect(singleton != updated)
        #expect(singleton != empty)

        later.wordIndex = 60
        let moved = try await signature(in: host.view)
        #expect(AnnotationListLogic.positionLabel(wordIndex: later.wordIndex) == "Word 61")
        #expect(moved != singleton, "Moving a bookmark must update its displayed position")
        later.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let redated = try await signature(in: host.view)
        #expect(redated != moved, "The row must display its current creation date")

        fixture.container.mainContext.delete(later)
        try fixture.container.mainContext.save()
        let deleted = try await signature(in: host.view)
        #expect(try fixture.container.mainContext.fetchCount(FetchDescriptor<Bookmark>()) == 0)
        #expect(AnnotationListLogic.ordered(fixture.book.bookmarks).isEmpty)
        #expect(deleted == empty, "Deleting the last bookmark must restore the empty state")
    }

    @Test func highlightsRenderEmptySortedUpdatedAndDeletedStates() async throws {
        let fixture = try Fixture()
        let host = UIHostingController(rootView: HighlightListView(book: fixture.book, engine: fixture.engine)
            .modelContainer(fixture.container))
        let window = try hostInWindow(host)
        defer { window.isHidden = true }
        let empty = try await signature(in: host.view)
        #expect(AnnotationListLogic.ordered(fixture.book.highlights).isEmpty)
        #expect(Set(empty).count > 8)

        let later = Highlight(startWordIndex: 40, endWordIndex: 46, highlightedText: "Later highlighted passage")
        let first = Highlight(startWordIndex: 0, endWordIndex: 0, highlightedText: "Opening")
        let tied = Highlight(startWordIndex: 0, endWordIndex: 3, highlightedText: "Another opening highlighted passage")
        first.createdAt = Date(timeIntervalSince1970: 1_000)
        tied.createdAt = Date(timeIntervalSince1970: 2_000)
        later.createdAt = Date(timeIntervalSince1970: 3_000)
        fixture.book.highlights = [later, tied, first]
        try fixture.container.mainContext.save()
        let populated = try await signature(in: host.view)
        let ordered = AnnotationListLogic.ordered(fixture.book.highlights)
        #expect(ordered.map(\.id) == [first.id, tied.id, later.id])
        #expect(ordered.map { AnnotationListLogic.rangeLabel(startWordIndex: $0.startWordIndex,
                                                           endWordIndex: $0.endWordIndex) }
            == ["Words 1–1", "Words 1–4", "Words 41–47"])
        #expect(ordered.map(\.wordSpan) == [1, 4, 7])
        #expect(populated != empty)

        first.highlightedText = "CHANGED: a visibly different highlighted passage"
        let updated = try await signature(in: host.view)
        let passageChanged = updated != populated
        #expect(passageChanged, "Changing highlighted text must change the rendered row")
        #expect(ordered.first?.highlightedText == "CHANGED: a visibly different highlighted passage")

        fixture.book.highlights = [first, later, tied]
        let reordered = try await signature(in: host.view)
        #expect(reordered == updated, "Relationship insertion order must not change display order")

        let doomed = AnnotationListLogic.highlightsToDelete(at: IndexSet([0, 1]), from: ordered)
        #expect(doomed.map(\.id) == [first.id, tied.id])
        for highlight in doomed { fixture.container.mainContext.delete(highlight) }
        try fixture.container.mainContext.save()
        let singleton = try await signature(in: host.view)
        #expect(fixture.book.highlights.map(\.id) == [later.id])
        #expect(singleton != updated)
        #expect(singleton != empty)

        later.endWordIndex = 47
        let extended = try await signature(in: host.view)
        #expect(AnnotationListLogic.rangeLabel(startWordIndex: later.startWordIndex,
                                               endWordIndex: later.endWordIndex) == "Words 41–48")
        #expect(later.wordSpan == 8)
        #expect(extended != singleton, "Extending a highlight must update its range and word count")
        later.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let redated = try await signature(in: host.view)
        #expect(redated != extended, "The row must display its current creation date")

        fixture.container.mainContext.delete(later)
        try fixture.container.mainContext.save()
        let deleted = try await signature(in: host.view)
        #expect(try fixture.container.mainContext.fetchCount(FetchDescriptor<Highlight>()) == 0)
        #expect(AnnotationListLogic.ordered(fixture.book.highlights).isEmpty)
        #expect(deleted == empty, "Deleting the last highlight must restore the empty state")
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let book: Book
        let engine = RSVPEngine()

        init() throws {
            container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            book = Book(title: "Annotations", author: "Reader",
                        extractedText: (0..<80).map { "word\($0)" }.joined(separator: " "),
                        sourceFileName: "annotations.txt")
            container.mainContext.insert(book)
            try container.mainContext.save()
            engine.load(words: book.words, startingAt: 0)
        }
    }

    private func hostInWindow<Content: View>(_ host: UIHostingController<Content>) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }

    private func signature(in view: UIView) async throws -> [UInt32] {
        // List creates UIKit cells on a subsequent run-loop turn. Every caller asserts the
        // resulting state; this is a render-settling interval, not an assertion-free holder.
        try await Task.sleep(for: .milliseconds(300))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image {
            view.layer.render(in: $0.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        let data = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let stride = cgImage.bitsPerPixel / 8
        #expect(stride == 4)
        var samples: [UInt32] = []
        // Omit system navigation/status chrome; inspect the actual annotation content.
        for y in Swift.stride(from: 110, to: cgImage.height - 40, by: 3) {
            for x in Swift.stride(from: 12, to: cgImage.width - 12, by: 3) {
                let offset = y * cgImage.bytesPerRow + x * stride
                samples.append(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
            }
        }
        return samples
    }
}
