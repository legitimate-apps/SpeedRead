import SwiftUI
import Testing
import WatchConnectivity
@testable import SpeedReadWatch_Watch_App

@Suite("Watch view rendering")
@MainActor
struct WatchViewRenderingTests {
    @Test func libraryRendersDistinctEmptyReceivingAndPopulatedStates() throws {
        let service = WatchSyncService(session: RenderingWatchSession())
        let emptySignatures = try renderSignatures(
            WatchLibraryContent(syncService: service, showRSVP: .constant(false))
        )

        service.isReceiving = true
        service.receivingTitle = "Incoming Book"
        let receivingSignatures = try renderSignatures(
            WatchLibraryContent(syncService: service, showRSVP: .constant(false))
        )

        let current = makeBook(
            title: "A Current Book",
            author: "Reader",
            index: 50,
            wordCount: 100,
            added: 200
        )
        let unread = makeBook(
            title: "A Waiting Book",
            author: "Writer",
            index: 0,
            wordCount: 80,
            added: 100
        )
        service.library = WatchLibrary(
            books: [unread, current],
            currentBookId: current.id
        )
        service.isReceiving = false
        _ = try renderSignatures(
            WatchLibraryContent(syncService: service, showRSVP: .constant(false))
        )

        #expect(WatchLibraryLogic.state(isReceiving: false, library: .empty) == .empty)
        #expect(WatchLibraryLogic.state(isReceiving: true, library: .empty) == .receiving)
        #expect(WatchLibraryLogic.state(isReceiving: false, library: service.library) == .books)
        #expect(WatchLibraryPresentation.progressText(for: current) == "50% complete")
        #expect(emptySignatures.count > 2)
        #expect(receivingSignatures.count > 2)
        #expect(receivingSignatures != emptySignatures)
    }

    @Test func detailRendersTheLatestSyncedProgressRatherThanItsStaleNavigationValue() throws {
        let service = WatchSyncService(session: RenderingWatchSession())
        let stale = makeBook(
            title: "Synced Book",
            author: "Author",
            index: 10,
            wordCount: 100,
            added: 100
        )
        var latest = stale
        latest.lastReadIndex = 75
        service.library = WatchLibrary(books: [latest], currentBookId: latest.id)

        let staleService = WatchSyncService(session: RenderingWatchSession())
        staleService.library = WatchLibrary(books: [stale], currentBookId: stale.id)
        let staleSignatures = try renderSignatures(
            WatchBookDetailContent(book: stale, onRead: {}, onRequestRemove: {})
                .background(Color.inkBlack)
        )
        let latestSignatures = try renderSignatures(
            WatchBookDetailContent(
                book: WatchBookDetailPresentation.latestBook(for: stale, in: service.library),
                onRead: {},
                onRequestRemove: {}
            )
            .background(Color.inkBlack)
        )

        let resolved = WatchBookDetailPresentation.latestBook(for: stale, in: service.library)
        #expect(resolved.lastReadIndex == 75)
        #expect(WatchBookDetailPresentation.progressPercentage(for: resolved) == 75)
        #expect(staleSignatures.count > 5)
        #expect(latestSignatures.count > 5)
        #expect(latestSignatures != staleSignatures)
    }

    private func renderSignatures<Content: View>(_ content: Content) throws -> Set<[UInt8]> {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 198, height: 242)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        var signatures: Set<[UInt8]> = []
        for y in stride(from: 0, to: image.height, by: 8) {
            for x in stride(from: 0, to: image.width, by: 8) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                signatures.insert(Array(UnsafeBufferPointer(
                    start: bytes + offset,
                    count: min(4, bytesPerPixel)
                )))
            }
        }
        return signatures
    }

    private func makeBook(
        title: String,
        author: String,
        index: Int,
        wordCount: Int,
        added: TimeInterval
    ) -> WatchBook {
        WatchBook(
            id: UUID(),
            title: title,
            author: author,
            text: (0..<wordCount).map { "word\($0)" }.joined(separator: " "),
            lastReadIndex: index,
            lastReadDate: Date(timeIntervalSince1970: added),
            wordCount: wordCount,
            dateAdded: Date(timeIntervalSince1970: added)
        )
    }
}

@MainActor
private final class RenderingWatchSession: WatchConnectivitySession {
    struct Transfer {}

    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .notActivated
    var isReachable = false

    func activate() {}

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    ) {}

    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer {
        Transfer()
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {}
}
