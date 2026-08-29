import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

@Suite("Reading view rendering")
@MainActor
struct ReadingViewRenderingTests {
    @Test func readerBodyRunsItsSessionLoadTaskWhenHosted() async throws {
        let (container, book) = try makeStoredBook(text: "alpha beta\n\ngamma", index: 2)
        let session = ReaderSession()
        let root = ReaderView(book: book, session: session)
            .modelContainer(container)
            .environmentObject(WatchSyncService.shared)
        let host = UIHostingController(rootView: root)
        let window = try hostInWindow(host)
        defer { window.isHidden = true }

        await waitUntil { session.cachedWords.count == 3 }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let visualSignatures = renderedPixelSignatures(in: host.view)

        #expect(session.cachedWords == ["alpha", "beta", "gamma"])
        #expect(session.paragraphs.count == 2)
        #expect(visualSignatures.count > 5)
        #expect(host.view.bounds.width == 390)
        #expect(host.view.bounds.height == 844)
    }

    @Test func rsvpBodyLoadsItsEngineAtThePersistedWordWhenHosted() async throws {
        let (container, book) = try makeStoredBook(text: "zero one two", index: 1)
        let engine = RSVPEngine()
        let presentation = RSVPPresentationSession()
        let root = RSVPView(book: book, engine: engine, presentation: presentation)
            .modelContainer(container)
            .environmentObject(WatchSyncService.shared)
        let host = UIHostingController(rootView: root)
        let window = try hostInWindow(host)
        defer { window.isHidden = true }

        await waitUntil { engine.totalWords == 3 }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let visualSignatures = renderedPixelSignatures(in: host.view)

        #expect(presentation.cachedWords == ["zero", "one", "two"])
        #expect(engine.currentIndex == 1)
        #expect(engine.currentWord == "one")
        #expect(visualSignatures.count > 5)
        #expect(host.view.bounds.width == 390)
        #expect(host.view.bounds.height == 844)
    }

    @Test func behaviorConstantsStayInternallyCoherent() {
        #expect(ReaderConfig.Classic.fontSizeRange.contains(ReaderConfig.Classic.defaultFontSize))
        #expect(ReaderConfig.Classic.lineSpacingRange.contains(ReaderConfig.Classic.defaultLineSpacing))
        #expect(ReaderConfig.Classic.rsvpTransitionDelay < ReaderConfig.Classic.wordFlashDuration)
        #expect(ReaderConfig.RSVP.scrubActivationDistance < ReaderConfig.RSVP.basePointsPerWord)
        #expect(ReaderConfig.RSVP.wpmStep > 0)
        #expect(ReaderConfig.RSVP.hapticWordInterval > 0)
    }

    @Test func readerSheetsRenderNonemptyNamedStates() async throws {
        let (container, book) = try makeStoredBook(text: "zero one two", index: 1)

        let settings = ReaderSettingsSheet(
            fontSize: .constant(ReaderConfig.Classic.defaultFontSize),
            lineSpacing: .constant(ReaderConfig.Classic.defaultLineSpacing),
            themeMode: .constant(ReaderThemeMode.parchment.rawValue)
        )
        let settingsSignatures = try await renderPixelSignatures(settings)
        #expect(settingsSignatures.count > 5)

        let bookmarkSignatures = try await renderPixelSignatures(
            ReaderBookmarkPicker(book: book) { _ in }
                .modelContainer(container)
        )
        #expect(bookmarkSignatures.count > 2)

        let highlightSignatures = try await renderPixelSignatures(
            ReaderHighlightPicker(book: book) { _ in }
                .modelContainer(container)
        )
        #expect(highlightSignatures.count > 2)
    }

    private func makeStoredBook(text: String, index: Int) throws -> (ModelContainer, Book) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
            Bookmark.self,
            Highlight.self,
            configurations: configuration
        )
        let book = Book(
            title: "Rendered Book",
            author: "Author",
            extractedText: text,
            sourceFileName: "rendered.txt"
        )
        book.lastReadWordIndex = index
        container.mainContext.insert(book)
        try container.mainContext.save()
        return (container, book)
    }

    private func hostInWindow<Content: View>(_ host: UIHostingController<Content>) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }

    private func renderPixelSignatures<Content: View>(_ content: Content) async throws -> Set<[UInt8]> {
        let host = UIHostingController(rootView: content)
        let window = try hostInWindow(host)
        defer { window.isHidden = true }
        await Task.yield()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return renderedPixelSignatures(in: host.view)
    }

    private func renderedPixelSignatures(in view: UIView) -> Set<[UInt8]> {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }

        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        var signatures: Set<[UInt8]> = []
        for y in stride(from: 0, to: cgImage.height, by: 20) {
            for x in stride(from: 0, to: cgImage.width, by: 20) {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                signatures.insert(Array(UnsafeBufferPointer(start: bytes + offset, count: min(4, bytesPerPixel))))
            }
        }
        return signatures
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}
