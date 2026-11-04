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

    @Test func aReaderTornDownWithItsTaskQueuedLeavesTheBookReadable() async throws {
        let (book, session) = try await hostAndTearDownReader()

        // Nothing here holds the container or the host now. Whatever the torn-down reader left
        // queued runs during these yields, and if the container had gone with the test's locals,
        // reading the book would trap and take the test host down.
        for _ in 0..<50 { await Task.yield() }

        #expect(session.cachedWords == ["alpha", "beta", "gamma"])
        #expect(book.lastReadWordIndex == 2)
    }

    private func hostAndTearDownReader() async throws -> (Book, ReaderSession) {
        let (container, book) = try makeStoredBook(text: "alpha beta gamma", index: 2)
        let session = ReaderSession()
        let host = UIHostingController(rootView: ReaderView(book: book, session: session)
            .modelContainer(container)
            .environmentObject(WatchSyncService.shared))
        let window = try hostInWindow(host)
        await waitUntil { session.cachedWords.count == 3 }
        // Commits the update that queues `.task(id: cachedWords.count)`, then leaves before it runs.
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.isHidden = true
        window.rootViewController = nil
        return (book, session)
    }

    @Test("RSVP exposes play and pause as an assistive-technology control")
    func rsvpPlaybackAffordanceRemainsAccessibleInBothStates() throws {
        // The static body type: evaluating `body` would need the hosted environment objects.
        let bodyType = String(reflecting: RSVPView.Body.self)

        #expect(bodyType.contains("RSVPPlaybackControl"))
        #expect(RSVPPlaybackControl.accessibilityIdentifier == "rsvp-playback-toggle")
        #expect(RSVPPlaybackControl.accessibilityLabel(isPlaying: false) == "Play")
        #expect(RSVPPlaybackControl.accessibilityLabel(isPlaying: true) == "Pause")
    }

    @Test func behaviorConstantsStayInternallyCoherent() {
        #expect(ReaderConfig.Classic.fontSizeRange.contains(ReaderConfig.Classic.defaultFontSize))
        #expect(ReaderConfig.Classic.lineSpacingRange.contains(ReaderConfig.Classic.defaultLineSpacing))
        #expect(ReaderConfig.Classic.rsvpTransitionDelay < ReaderConfig.Classic.wordFlashDuration)
        #expect(ReaderConfig.RSVP.scrubActivationDistance > 0)
        #expect(ReaderConfig.RSVP.wpmStep > 0)
        #expect(ReaderConfig.RSVP.settleDuration <= ReaderConfig.RSVP.flingDurationRange.lowerBound)
        #expect(ReaderConfig.RSVP.flingMinimumVelocity > 0 && ReaderConfig.RSVP.flingMaximumWords > 0)
    }

    @Test func readerViewReadingEstimateClampsSpeedAndReportsFinishBranch() {
        let longBook = Book(
            title: "Estimate",
            author: "Author",
            extractedText: "zero one two three four five",
            sourceFileName: "estimate.txt"
        )
        // Completion is a persisted fact; the cursor still identifies a valid word.
        longBook.lastReadWordIndex = longBook.wordCount - 1
        longBook.finishedAt = Date(timeIntervalSince1970: 100)
        #expect(longBook.progress == 1)
        #expect(ReaderView.readingEstimate(book: longBook, lastWPM: 250) == "100% · finished")

        // A final-word jump remains unfinished. Actual playback completion reaches the
        // same cursor with didFinish=true, so a real commit can now produce the branch.
        let committed = ReadingPositionCoordinator.clampedIndex(Int.max, wordCount: longBook.wordCount)
        #expect(committed == longBook.wordCount - 1)
        let saver = EstimateSaver()
        let sync = EstimateSync()
        _ = ReadingPositionCoordinator.commit(committed, wordCount: longBook.wordCount,
            book: longBook, saver: saver, sync: sync)
        #expect(longBook.finishedAt == nil)
        #expect(ReaderView.readingEstimate(book: longBook, lastWPM: 250) != "100% · finished")
        #expect(longBook.progress < 1.0)
        _ = ReadingPositionCoordinator.commit(committed, wordCount: longBook.wordCount,
            book: longBook, saver: saver, sync: sync, didFinish: true)
        #expect(longBook.finishedAt != nil)
        #expect(longBook.progress == 1)
        #expect(ReaderView.readingEstimate(book: longBook, lastWPM: 250) == "100% · finished")

        let midBook = Book(
            title: "Estimate",
            author: "Author",
            extractedText: Array(repeating: "word", count: 40).joined(separator: " "),
            sourceFileName: "estimate-2.txt"
        )
        midBook.lastReadWordIndex = 10
        #expect(ReaderView.readingEstimate(book: midBook, lastWPM: 1) == "25% · 1 min left at 60 WPM")

        let nearDone = Book(
            title: "Estimate",
            author: "Author",
            extractedText: "alpha beta gamma",
            sourceFileName: "estimate-3.txt"
        )
        nearDone.lastReadWordIndex = 2
        #expect(ReaderView.readingEstimate(book: nearDone, lastWPM: 1200) == "66% · <1 min left at 1200 WPM")
    }

    @Test func readerSheetsRenderEmptyAndNonemptyAnnotationLists() async throws {
        let (container, book) = try makeStoredBook(text: "zero one two three", index: 1)

        let earlyBookmark = Bookmark(wordIndex: 1, previewText: "one")
        let lateBookmark = Bookmark(wordIndex: 0, previewText: "zero")
        let nearHighlight = Highlight(startWordIndex: 3, endWordIndex: 3, highlightedText: "three")
        let distantHighlight = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "zero one")

        book.bookmarks.append(contentsOf: [earlyBookmark, lateBookmark])
        book.highlights.append(contentsOf: [nearHighlight, distantHighlight])
        container.mainContext.insert(earlyBookmark)
        container.mainContext.insert(lateBookmark)
        container.mainContext.insert(nearHighlight)
        container.mainContext.insert(distantHighlight)

        let emptyBook = Book(
            title: "No annotations",
            author: "Author",
            extractedText: "empty",
            sourceFileName: "empty.txt"
        )
        container.mainContext.insert(emptyBook)

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

        let emptyBookmarkSignatures = try await renderPixelSignatures(
            ReaderBookmarkPicker(book: emptyBook) { _ in }
                .modelContainer(container)
        )
        #expect(emptyBookmarkSignatures.count > 1)
        #expect(bookmarkSignatures != emptyBookmarkSignatures)

        let bookmarkPicker = ReaderBookmarkPicker(book: book) { _ in }
        let sortedBookmarks = bookmarkPicker.orderedBookmarks()
        #expect(sortedBookmarks.map(\.wordIndex) == [0, 1])

        let highlightSignatures = try await renderPixelSignatures(
            ReaderHighlightPicker(book: book) { _ in }
                .modelContainer(container)
        )
        #expect(highlightSignatures.count > 2)

        let emptyHighlightSignatures = try await renderPixelSignatures(
            ReaderHighlightPicker(book: emptyBook) { _ in }
                .modelContainer(container)
        )
        #expect(emptyHighlightSignatures.count > 1)
        #expect(highlightSignatures != emptyHighlightSignatures)

        let highlightPicker = ReaderHighlightPicker(book: book) { _ in }
        let sortedHighlights = highlightPicker.orderedHighlights()
        #expect(sortedHighlights.map(\.startWordIndex) == [0, 3])
    }

    @Test func readerSheetsRouteRowSelectionByIndexThroughCallbackMethods() async throws {
        let (container, book) = try makeStoredBook(text: "zero one two three four five", index: 0)

        let early = Bookmark(wordIndex: 4, previewText: "four")
        let late = Bookmark(wordIndex: 1, previewText: "one")
        let rangeOne = Highlight(startWordIndex: 3, endWordIndex: 4, highlightedText: "three four")
        let rangeTwo = Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "zero one")

        book.bookmarks.append(contentsOf: [early, late])
        book.highlights.append(contentsOf: [rangeOne, rangeTwo])
        container.mainContext.insert(early)
        container.mainContext.insert(late)
        container.mainContext.insert(rangeOne)
        container.mainContext.insert(rangeTwo)

        var selectedBookmark: Int?
        var selectedHighlight: Int?

        let bookmarkPicker = ReaderBookmarkPicker(book: book) { index in
            selectedBookmark = index
        }
        bookmarkPicker.select(early)
        #expect(selectedBookmark == early.wordIndex)

        let highlightPicker = ReaderHighlightPicker(book: book) { index in
            selectedHighlight = index
        }
        highlightPicker.select(rangeTwo)
        #expect(selectedHighlight == rangeTwo.startWordIndex)

        #expect(selectedBookmark != nil)
        #expect(selectedHighlight != nil)
    }

    @Test func readerSheetRowLabelsRenderDifferentPayloadsForDifferentRows() async throws {
        let (container, book) = try makeStoredBook(text: "alpha beta gamma delta", index: 0)
        container.mainContext.insert(book)

        let bookmarkA = Bookmark(wordIndex: 0, previewText: "alpha beta")
        let bookmarkB = Bookmark(wordIndex: 2, previewText: "gamma delta")
        let highlightA = Highlight(startWordIndex: 0, endWordIndex: 0, highlightedText: "alpha")
        let highlightB = Highlight(startWordIndex: 1, endWordIndex: 2, highlightedText: "beta gamma")

        let bookmarkPicker = ReaderBookmarkPicker(book: book) { _ in }
        let bookmarkASignatures = try await renderPixelSignatures(bookmarkPicker.rowLabel(for: bookmarkA))
        let bookmarkBSignatures = try await renderPixelSignatures(bookmarkPicker.rowLabel(for: bookmarkB))
        #expect(!bookmarkASignatures.isEmpty)
        #expect(!bookmarkBSignatures.isEmpty)
        #expect(bookmarkASignatures != bookmarkBSignatures)

        let highlightPicker = ReaderHighlightPicker(book: book) { _ in }
        let highlightASignatures = try await renderPixelSignatures(highlightPicker.rowLabel(for: highlightA))
        let highlightBSignatures = try await renderPixelSignatures(highlightPicker.rowLabel(for: highlightB))
        #expect(!highlightASignatures.isEmpty)
        #expect(!highlightBSignatures.isEmpty)
        #expect(highlightASignatures != highlightBSignatures)
    }

    // MARK: - "Reading on Apple Watch"

    private func card(at word: Int, onReadHere: @escaping () -> Void = {}) -> ReadingElsewhereCard {
        ReadingElsewhereCard(
            presence: RemotePresence(bookId: UUID(), wordIndex: word, playStartedAt: .distantPast, sentAt: .distantPast),
            wordCount: 100,
            chapters: [ChapterMark(title: "One", startWordIndex: 0), ChapterMark(title: "Two", startWordIndex: 50)],
            background: .black, foreground: .white, accent: .yellow, onAccent: .black, onReadHere: onReadHere)
    }

    @Test func theReadingElsewhereCardShowsWhereTheWatchIs() throws {
        let early = try PresentationRaster(card(at: 3), width: 390, height: 160)
        let control = try PresentationRaster(card(at: 3), width: 390, height: 160)
        let later = try PresentationRaster(card(at: 75), width: 390, height: 160)
        #expect(early == control, "Rendering is deterministic, so a difference is the text")
        #expect(early != later, "The chapter and percentage follow the watch's word")
        var tapped = false
        card(at: 3, onReadHere: { tapped = true }).onReadHere()
        #expect(tapped)
    }

    private func hostedPNG(
        rsvp: Bool, book: Book, container: ModelContainer, service: WatchSyncService
    ) async throws -> Data {
        let view: AnyView = rsvp
            ? AnyView(RSVPView(book: book, engine: RSVPEngine()))
            : AnyView(ReaderView(book: book, session: ReaderSession()))
        let host = UIHostingController(rootView: view.modelContainer(container).environmentObject(service))
        let window = try hostInWindow(host)
        defer { window.isHidden = true }
        for _ in 0..<20 { await Task.yield() }
        return try await settledPNG(of: host.view)
    }

    @Test(arguments: [false, true])
    func readerAndRSVPShowTheCardOnlyWhileTheWatchReadsThisBook(rsvp: Bool) async throws {
        let (container, book) = try makeStoredBook(text: "zero one two three", index: 1)
        let quiet = WatchSyncService(session: FakeWatchConnectivitySession())
        let reading = WatchSyncService(session: FakeWatchConnectivitySession())
        let now = Date()
        reading.clock = { now }
        reading.receivePosition(.init(bookId: book.id, bookTitle: book.title, wordIndex: 1, timestamp: now,
                                      isPlaying: true, playStartedAt: now, sentAt: now))
        #expect(reading.remotePresence(for: book.id) != nil)
        let elsewhere = WatchSyncService(session: FakeWatchConnectivitySession())
        elsewhere.clock = { now }
        elsewhere.receivePosition(.init(bookId: UUID(), bookTitle: "Other", wordIndex: 1, timestamp: now,
                                        isPlaying: true, playStartedAt: now, sentAt: now))

        let first = try await hostedPNG(rsvp: rsvp, book: book, container: container, service: quiet)
        let control = try await hostedPNG(rsvp: rsvp, book: book, container: container, service: quiet)
        #expect(first == control, "The quiet render is stable, so a difference is the card")
        #expect(try await hostedPNG(rsvp: rsvp, book: book, container: container, service: reading) != first)
        #expect(try await hostedPNG(rsvp: rsvp, book: book, container: container, service: elsewhere) == first, "Another book being read leaves this one alone")
    }

    /// The first frame that matches the one before it. On iOS 27 two renders of an identical RSVP
    /// screen came out different (236,139 and 236,273 bytes), so a single frame isn't a stable
    /// picture of a screen. RSVP animates its progress bar for 0.1 s as the engine loads, which is
    /// the likely reason.
    private func settledPNG(of view: UIView) async throws -> Data {
        func frame() throws -> Data {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
            return try #require(image.pngData())
        }
        var previous = try frame()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(150))
            let next = try frame()
            if next == previous { return next }
            previous = next
        }
        return previous
    }

    private func makeStoredBook(text: String, index: Int) throws -> (ModelContainer, Book) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
            Bookmark.self,
            Highlight.self,
            configurations: configuration
        ).keptAliveForHostedViews()
        let book = Book(
            title: "Rendered Book",
            author: "Author",
            extractedText: text,
            sourceFileName: "rendered.txt"
        )
        book.lastReadWordIndex = index
        book.browseWordIndex = index
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

@MainActor
private final class EstimateSaver: ReadingPositionSaving {
    func save() throws {}
}

@MainActor
private final class EstimateSync: ReadingPositionSyncing {
    func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int, timestamp: Date, furthestReadWordIndex: Int, didFinish: Bool, finishedAt: Date?) {}
}
