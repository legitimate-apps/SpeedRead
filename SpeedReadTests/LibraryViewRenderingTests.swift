import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

@Suite("Library view rendering")
@MainActor
struct LibraryViewRenderingTests {
    @Test func emptyLibraryLoadsAndRendersTheBundledShelfWhenHosted() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
            configurations: configuration
        )
        let root = LibraryView()
            .modelContainer(container)
            .environment(ThemeManager())
            .environmentObject(WatchSyncService.shared)
        let host = UIHostingController(rootView: root)
        let window = try hostInWindow(host)
        defer { window.isHidden = true }

        await waitUntil {
            (try? container.mainContext.fetchCount(FetchDescriptor<Book>())) == 4
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        let renderedSignatures = pixelSignatures(in: host.view)

        #expect(books.count == 4)
        #expect(Set(books.map(\.sourceFileName)) == [
            "TheYellowWallpaper.epub",
            "TheMetamorphosis.epub",
            "AChristmasCarol.epub",
            "AChristmasCarol.pdf"
        ])
        #expect(books.allSatisfy { !$0.words.isEmpty })
        #expect(renderedSignatures.count > 8)
        #expect(host.view.bounds == CGRect(x: 0, y: 0, width: 390, height: 844))
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

    private func pixelSignatures(in view: UIView) -> Set<[UInt8]> {
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
                signatures.insert(Array(UnsafeBufferPointer(
                    start: bytes + offset,
                    count: min(4, bytesPerPixel)
                )))
            }
        }
        return signatures
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}
