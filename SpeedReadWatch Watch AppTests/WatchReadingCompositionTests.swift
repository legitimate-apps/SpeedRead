import SwiftUI
import Testing
import WatchConnectivity
@testable import SpeedReadWatch_Watch_App

@Suite("Watch reading composition")
@MainActor
struct WatchReadingCompositionTests {
    private let storage: WatchTestStorage
    init() throws { storage = try WatchTestStorage() }

    @Test func chapterAndCrownBrowsingPersistLocallyAndRestoreUsesLatestPhonePosition() throws {
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        let book = makeBook()
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let session = WatchRSVPSession()
        var crown = 0.0
        var showing = true
        let content = WatchRSVPContent(syncService: service, session: session,
            showSettings: Binding(get: { showing }, set: { showing = $0 }),
            crownValue: Binding(get: { crown }, set: { crown = $0 }), wpm: 420)
        content.load()
        #expect(session.engine.currentIndex == 3)
        #expect(session.engine.wpm == 420)
        let initial = try PresentationRaster(content.surface, width: 198, height: 242)
        #expect(content.settings.currentWordIndex == 3)
        #expect(content.settings.chapters == book.chapters)
        content.settings.onSelectChapter(book.chapters[1])
        #expect(!showing)
        #expect(session.engine.currentIndex == 10)
        #expect(storage.store.load().currentBook?.browseWordIndex == 10)
        #expect(storage.store.load().currentBook?.lastReadIndex == 2)
        #expect(wire.contexts.isEmpty)
        let chapter = try PresentationRaster(content.surface, width: 198, height: 242)
        #expect(initial != chapter, "The selected chapter must change the visible word")
        crown += 2
        content.seek(crown)
        #expect(session.engine.currentIndex == 8)
        #expect(storage.store.load().currentBook?.browseWordIndex == 8)
        #expect(wire.contexts.isEmpty)
        service.library.updatePosition(bookId: book.id, index: 6, timestamp: Date(), furthestReadWordIndex: 12)
        content.settings.restoreReadingPosition()
        #expect(session.engine.currentIndex == 6)
        #expect(storage.store.load().currentBook?.browseWordIndex == 6)
        #expect(wire.contexts.isEmpty)
        crown = -500
        content.synchronizePosition()
        #expect(crown >= 0)
        content.disappear()
        #expect(wire.contexts.isEmpty, "Merely browsing then closing must never sync a reading position")
    }

    @Test func playbackCommitsButSettingsPauseAndPausedBrowsingDoNot() throws {
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        let book = makeBook()
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let session = WatchRSVPSession()
        var showing = false
        var crown = 0.0
        let content = WatchRSVPContent(syncService: service, session: session,
            showSettings: Binding(get: { showing }, set: { showing = $0 }),
            crownValue: Binding(get: { crown }, set: { crown = $0 }), wpm: 300)
        content.load()
        let paused = try PresentationRaster(content.surface, width: 198, height: 242)
        content.togglePlayback()
        #expect(session.engine.state == .playing)
        #expect(wire.contexts.count == 1)
        #expect(wire.contexts.first?["wordIndex"] as? Int == 3)
        #expect(storage.store.load().currentBook?.lastReadIndex == 3)
        let playing = try PresentationRaster(content.surface, width: 198, height: 242)
        #expect(paused != playing)
        content.seek(crown + 5)
        #expect(session.engine.currentIndex == 3)
        content.synchronizePosition()
        #expect(wire.contexts.count == 1)
        content.togglePlayback()
        #expect(session.engine.state == .paused)
        #expect(wire.contexts.count == 1)
        content.togglePlayback()
        #expect(wire.contexts.count == 2)
        content.openSettings()
        #expect(showing)
        #expect(session.engine.state == .paused)
        #expect(wire.contexts.count == 2)
        content.disappear()
        #expect(wire.contexts.count == 3)
        #expect(wire.contexts.last?["wordIndex"] as? Int == 3)
    }

    @Test func missingBookActionsAreSafeAndDoNotCreateAStoreOrSendPosition() throws {
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        let session = WatchRSVPSession()
        var crown = 900.0
        let content = WatchRSVPContent(syncService: service, session: session,
            showSettings: .constant(false), crownValue: Binding(get: { crown }, set: { crown = $0 }), wpm: 300)
        content.load()
        content.selectChapter(ChapterMark(title: "Stale sheet", startWordIndex: 10))
        content.restoreReadingPosition()
        content.togglePlayback()
        content.seek(1)
        content.synchronizePosition()
        content.disappear()
        #expect(content.settings.chapters.isEmpty)
        #expect(crown == 0)
        #expect(!session.engine.isLoaded)
        #expect(wire.contexts.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.directory.path).isEmpty)
    }

    @Test func appFixturePreparationPreservesOrdinaryLibraryAndSeedsOnlyRequestedDestinations() throws {
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        let book = makeBook()
        let original = WatchLibrary(books: [book], currentBookId: book.id)
        service.library = original
        #expect(!SpeedReadWatch_Watch_AppApp.prepareLaunch(destination: .library, syncService: service))
        #expect(service.library == original)
        #expect(!SpeedReadWatch_Watch_AppApp.prepareLaunch(destination: .seededLibrary, syncService: service))
        let fixture = try #require(service.currentBook)
        #expect(fixture.title == "Crown Direction Fixture")
        #expect(fixture.words.count == 200)
        #expect(fixture.browseWordIndex == 100)
        #expect(service.library.books.count == 1)
        #expect(SpeedReadWatch_Watch_AppApp.prepareLaunch(destination: .crownDirectionFixture, syncService: service))
        #expect(service.currentBook == fixture)
        #expect(wire.activations == 0)
        #expect(wire.contexts.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.directory.path).isEmpty,
                "Fixture seeding must not overwrite the reader's persisted library")
    }

    @Test func appLibraryAppearanceLoadsInjectedStoreButRSVPFixtureNeverActivates() throws {
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        let saved = makeBook()
        try storage.store.save(WatchLibrary(books: [saved], currentBookId: saved.id))
        let libraryRoot = WatchAppRoot(syncService: service, launchesCrownDirectionFixture: false)
        // NavigationStack cannot be flattened. Its appearance can still be observed through
        // the injected store and session, so no claim is made about the placeholder pixels.
        _ = try PresentationRaster(libraryRoot, width: 198, height: 242)
        #expect(wire.activations == 1)
        #expect(wire.delegate === service)
        #expect(service.currentBook?.id == saved.id)
        _ = SpeedReadWatch_Watch_AppApp.prepareLaunch(destination: .crownDirectionFixture, syncService: service)
        let fixtureID = try #require(service.currentBook?.id)
        #expect(storage.store.load().currentBook?.id == saved.id,
                "Preparation itself must not write the fixture to disk")
        let fixtureRoot = WatchAppRoot(syncService: service, launchesCrownDirectionFixture: true)
        _ = try PresentationRaster(fixtureRoot, width: 198, height: 242)
        #expect(wire.activations == 1, "RSVP appearance must not activate or reload the library")
        #expect(service.currentBook?.id == fixtureID)
        #expect(wire.contexts.isEmpty)
        // RSVP's normal onAppear -> crown change records a local browse position. This also
        // proves the app root passed our injected service through the environment to RSVP.
        #expect(storage.store.load().currentBook?.id == fixtureID)

    }

    @Test(arguments: [false, true])
    func finishingOnWatchPersistsCompleteAndRereadingClearsIt(disappearFirst: Bool) async throws {
        // Mutation: drop didFinish between natural engine completion and the WCSession context.
        let wire = CompositionWatchSession()
        let service = WatchSyncService(session: wire, store: storage.store)
        // Sampled verbatim from SampleBooks/TheYellowWallpaper.epub, pg-header-heading.
        let text = "The Project Gutenberg eBook of The Yellow Wallpaper"
        let book = WatchBook(id: UUID(), title: "Completion", author: "", text: text,
            lastReadIndex: 0, lastReadDate: nil, wordCount: BookTokenizer.tokenize(text).count,
            dateAdded: .distantPast)
        service.library = WatchLibrary(books: [book], currentBookId: book.id)
        let session = WatchRSVPSession()
        let content = WatchRSVPContent(syncService: service, session: session,
            showSettings: .constant(false), crownValue: .constant(0), wpm: 1500)
        content.load()
        session.engine.seek(to: book.wordCount - 1)
        content.togglePlayback()
        let atLastWord = try #require(storage.store.load().currentBook)
        #expect(atLastWord.progress < 1, "Displaying the last word is not completion")
        let deadline = ContinuousClock.now + .seconds(3)
        while !session.engine.didFinish && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.engine.didFinish)
        if disappearFirst { content.disappear() } else { content.synchronizePosition() }
        let finished = try #require(storage.store.load().currentBook)
        #expect(finished.progress == 1)
        let completion = try #require(wire.contexts.last)
        #expect(completion["didFinish"] as? Bool == true)
        #expect(completion["finishedAt"] as? Double == finished.finishedAt?.timeIntervalSince1970)
        #expect(WatchBookDetailPresentation.progressPercentage(for: finished) == 100)
        #expect(WatchLibraryPresentation.progressText(for: finished) == "100% complete")
        content.disappear()
        #expect(storage.store.load().currentBook?.progress == 1)
        content.load()
        session.engine.seek(to: 0)
        content.synchronizePosition()
        #expect(storage.store.load().currentBook?.progress == 1, "Browsing does not clear completion")
        content.togglePlayback()
        content.togglePlayback()
        let rereading = try #require(storage.store.load().currentBook)
        #expect(rereading.lastReadIndex == 0)
        #expect(rereading.progress == 0)
        #expect(wire.contexts.last?["didFinish"] as? Bool == false)
        #expect(wire.contexts.last?["finishedAt"] == nil)
    }

    private func makeBook() -> WatchBook {
        WatchBook(id: UUID(), title: "Composition", author: "Reader",
                  text: (0..<20).map { "word\($0)" }.joined(separator: " "), lastReadIndex: 2,
                  lastReadDate: nil, browseWordIndex: 3, furthestReadWordIndex: 12,
                  wordCount: 20, dateAdded: Date(timeIntervalSince1970: 0),
                  chapters: [ChapterMark(title: "Opening", startWordIndex: 0),
                             ChapterMark(title: "Ending", startWordIndex: 10)])
    }
}

@MainActor
private final class CompositionWatchSession: WatchConnectivitySession {
    struct Transfer {}
    weak var delegate: (any WCSessionDelegate)?
    var activationState: WCSessionActivationState = .activated
    var isReachable = false
    var contexts: [[String: Any]] = []
    var activations = 0
    func activate() { activations += 1 }
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((any Error) -> Void)?) {}
    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer { Transfer() }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws { contexts.append(applicationContext) }
}
