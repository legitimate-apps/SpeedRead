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

    @Test func libraryImportSessionImportsAValidTextFileAndPersistsABook() throws {
        let container = try makeStoredContainer()
        let session = LibraryImportSession()
        let importURL = try writeTemporaryTextFile(
            named: "library-import.txt",
            contents: "reader session import test"
        )
        defer { try? FileManager.default.removeItem(at: importURL) }

        session.handleImport(.success([importURL]), modelContext: container.mainContext)

        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.sourceFileName == "library-import.txt")
        // TextFileExtractor.detectTitle derives the title from the CONTENT's first line, not the
        // filename -- the documented behaviour. Asserting the filename here was the test's error.
        #expect(books.first?.title == "reader session import test")
        #expect(books.first?.author == "Unknown Author")
        #expect(session.showError == false)
    }

    @Test func libraryImportSessionMapsFailureIntoAlertState() throws {
        let container = try makeStoredContainer()
        let session = LibraryImportSession()
        let simulatedError = NSError(
            domain: "speedread-library-import-tests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "simulated picker error"]
        )

        session.handleImport(.failure(simulatedError), modelContext: container.mainContext)

        #expect(session.showError)
        #expect(session.importError == "simulated picker error")
    }

    @Test func libraryImportSessionNoSelectionIsNoop() throws {
        let container = try makeStoredContainer()
        let session = LibraryImportSession()

        session.handleImport(.success([]), modelContext: container.mainContext)

        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.isEmpty)
        #expect(!session.showError)
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

    private func makeStoredContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
            configurations: configuration
        )
    }

    private func writeTemporaryTextFile(named: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(named)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(contents.data(using: .utf8)).write(to: url)
        return url
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
