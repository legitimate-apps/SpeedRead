import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

@Suite("OPDS server surface", .serialized)
@MainActor
struct OPDSServerSurfaceTests {
    @Test func browseEmptyPickerInvalidAndSelection() async throws {
        let f = try Fixture()
        defer { f.close() }
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        let empty = try await hosted.signature()
        #expect(Set(empty).count > 8)
        #expect(f.script.observed.isEmpty)
        let first = f.server("First")
        let second = f.server("Second", path: "second")
        try f.container.mainContext.save()
        let picker = try await hosted.signature()
        #expect(picker != empty)
        #expect(f.script.observed.isEmpty, "The picker must not contact any server")
        second.baseURLString = "http://["
        try f.container.mainContext.save()
        let select = f.select
        select(second.id)
        let invalid = try await hosted.signature()
        #expect(invalid != picker)
        #expect(second.lastUsedAt != nil)
        #expect(f.script.observed.isEmpty, "Invalid saved URLs must stop before networking")
        f.script.enqueue(try #require(first.baseURL), data: atom(books: ["Selected book"]))
        select(first.id)
        try await eventually { f.browse.displayEntries.map(\.title) == ["Selected book"] }
        #expect(first.lastUsedAt != nil)
        #expect(f.script.observed.map(\.url) == [first.baseURL])
        #expect(try await hosted.signature() != invalid)
        #expect(f.script.remaining == 0)
    }

    @Test func feedTransportFailureRetrySearchHitMissClearAndFailure() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        f.script.fail(f.base, held: true)
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        try await eventually { f.script.observed.count == 1 }
        #expect(f.browse.loading == true)
        let loading = try await hosted.signature()
        f.script.release()
        try await eventually { f.browse.loading == false }
        #expect(f.browse.error?.contains("Network error") == true)
        let failed = try await hosted.signature()
        #expect(failed != loading)
        #expect(server.lastUsedAt == nil)
        f.script.enqueue(f.base, data: atom(books: ["Original book"]))
        let retry = f.reload
        await retry()
        #expect(f.browse.displayEntries.map(\.title) == ["Original book"])
        #expect(f.browse.error == nil)
        #expect(server.lastUsedAt != nil)
        let loaded = try await hosted.signature()
        #expect(loaded != failed)
        let search = f.search
        f.script.enqueue(f.url("search/hit"), data: atom(books: ["Matching book"]))
        try await hosted.submitSearch("hit")
        #expect(f.browse.searchText == "hit")
        try await eventually { f.browse.displayEntries.map(\.title) == ["Matching book"] }
        #expect(f.browse.displayEntries.map(\.title) == ["Matching book"])
        let hit = try await hosted.signature()
        #expect(hit != loaded)
        f.script.enqueue(f.url("search/miss"), data: atom())
        try await hosted.submitSearch("miss")
        try await eventually { f.browse.displayEntries.map(\.title).isEmpty == true }
        #expect(f.browse.displayEntries.map(\.title).isEmpty == true)
        #expect(try await hosted.signature() != hit)
        await search("")
        #expect(f.browse.displayEntries.map(\.title) == ["Original book"])
        f.script.enqueue(f.url("search/broken"), status: 503)
        await search("broken")
        #expect(f.browse.error == "Server error (503). Try again later.")
        #expect(f.browse.displayEntries.map(\.title) == ["Original book"])
        #expect(f.script.observed.compactMap { $0.url?.lastPathComponent }
                == [f.base.lastPathComponent, f.base.lastPathComponent, "hit", "miss", "broken"])
        #expect(f.script.remaining == 0)
    }

    @Test func paginationRunsFromRowTaskAndFailureStopsFurtherPages() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.server()
        let next = f.url("page2")
        let last = f.url("page3")
        f.script.enqueue(f.base, data: atom(books: ["First page"], next: next))
        f.script.enqueue(next, data: atom(books: ["Second page"], next: last), held: true)
        f.script.fail(last, held: true)
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        try await eventually { f.script.observed.count == 2 }
        #expect(f.browse.displayEntries.map(\.title) == ["First page"])
        #expect(f.browse.loadingMore == true)
        let before = try await hosted.signature()
        // A second request while the row is loading must be ignored by the view's guard.
        let more = f.more
        await more()
        #expect(f.script.observed.count == 2)
        f.script.release()
        try await eventually { f.browse.displayEntries.map(\.title) == ["First page", "Second page"] }
        let after = try await hosted.signature()
        #expect(after != before)
        // Depending on row identity, SwiftUI may already have scheduled page three.
        let task = Task { await more() }
        try await eventually { f.script.observed.count == 3 }
        f.script.release()
        await task.value
        try await eventually { f.browse.loadingMore == false }
        #expect(f.browse.nextPageURL == nil)
        #expect(f.browse.error == nil)
        #expect(f.browse.displayEntries.map(\.title) == ["First page", "Second page"])
        await more()
        #expect(f.script.observed.map(\.url) == [f.base, next, last])
        #expect(f.script.remaining == 0)
    }

    @Test func browseCoverFetchAndCachedRefreshRenderTheRealRow() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.server()
        let cover = f.url("cover")
        let feed = atom(books: ["Illustrated book"], cover: cover)
        f.script.enqueue(f.base, data: feed)
        f.script.enqueue(cover, data: coverData(), held: true)
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        try await eventually { f.script.observed.count == 2 }
        let pending = try await hosted.signature()
        f.script.release()
        try await eventually { OPDSCoverCache.shared.image(for: cover) != nil }
        let rendered = try await hosted.signature()
        #expect(rendered != pending)
        #expect(f.browse.displayEntries.map(\.title) == ["Illustrated book"])
        f.script.enqueue(f.base, data: feed)
        await f.reload()
        #expect(try await hosted.signature() == rendered)
        #expect(f.script.observed.map(\.url) == [f.base, cover, f.base])
        #expect(f.script.remaining == 0)
    }

    @Test(arguments: [false, true])
    func browseCoverFailureDoesNotHideTheBook(transportFailure: Bool) async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.server()
        let cover = f.url("bad-cover")
        f.script.enqueue(f.base, data: atom(books: ["Book with unavailable cover"], cover: cover))
        if transportFailure { f.script.fail(cover) }
        else { f.script.enqueue(cover, data: Data("not image bytes".utf8)) }
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        try await eventually { f.script.observed.count == 2 }
        let pixels = try await hosted.signature()
        #expect(Set(pixels).count > 8)
        #expect(f.browse.displayEntries.map(\.title) == ["Book with unavailable cover"])
        #expect(f.browse.error == nil)
        #expect(OPDSCoverCache.shared.image(for: cover) == nil)
        #expect(f.script.observed.map(\.url) == [f.base, cover])
        #expect(f.script.remaining == 0)
    }

    @Test func serverEditorValidatesSavesAndTestsConnectionIncludingHTTP() async throws {
        let f = try Fixture()
        defer { f.close() }
        let hosted = try f.host(NavigationStack { ServerEditView(server: nil, session: f.editor) })
        defer { hosted.close() }
        _ = try await hosted.signature()
        #expect(f.editor.canSave == false)
        #expect(f.editor.testState == .idle)
        let empty = try await hosted.signature()
        let edit = f.edit
        let save = f.save
        let test = f.probeConnection
        edit("Saved catalog", "http://[", false)
        #expect(save() == false)
        #expect(f.editor.validationError?.contains("valid URL") == true)
        await test()
        #expect(f.editor.testState == .failure("Invalid URL"))
        #expect(f.script.observed.isEmpty)
        var components = try #require(URLComponents(url: f.base, resolvingAgainstBaseURL: true))
        components.scheme = "http"
        let plain = try #require(components.url)
        edit("Saved catalog", plain.absoluteString, false)
        #expect(save() == false)
        await test()
        #expect(f.editor.testState == .failure("Plain HTTP is disabled for this server"))
        #expect(f.editor.validationError?.contains("Allow plain HTTP") == true)
        #expect(f.script.observed.isEmpty)
        let insecureWarning = try await hosted.signature()
        #expect(insecureWarning != empty)
        edit("  Saved catalog  ", plain.absoluteString, true)
        f.script.enqueue(plain, data: atom(books: ["Probe book"]), held: true)
        let running = Task { await test() }
        try await eventually { f.script.observed.count == 1 }
        #expect(f.editor.testState == .running)
        let runningPixels = try await hosted.signature()
        #expect(runningPixels != insecureWarning)
        f.script.release()
        await running.value
        #expect(f.editor.testState == .success)
        #expect(try await hosted.signature() != runningPixels)
        f.script.enqueue(plain, status: 401)
        await test()
        #expect(f.editor.testState == .failure("Authentication failed (401). Check the username and password."))
        #expect(save())
        let saved = try f.container.mainContext.fetch(FetchDescriptor<OPDSServer>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Saved catalog")
        #expect(saved.first?.baseURL == plain)
        #expect(saved.first?.allowInsecureHTTP == true)
        #expect(f.editor.validationError == nil)
        #expect(f.script.remaining == 0)
    }

    @Test func existingEditorLoadsAndUpdatesWithoutDuplicatingServer() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server("Existing")
        let hosted = try f.host(NavigationStack { ServerEditView(server: server, session: f.editor) })
        defer { hosted.close() }
        try await eventually { f.editor.name == "Existing" }
        let before = try await hosted.signature()
        #expect(f.editor.urlString == f.base.absoluteString)
        f.edit("Updated", f.url("updated").absoluteString, false)
        #expect(try await hosted.signature() != before)
        f.script.fail(f.url("updated"))
        await f.probeConnection()
        if case .failure(let message) = f.editor.testState {
            #expect(message.contains("Network error"))
        } else { Issue.record("The editor must render the transport failure") }
        #expect(f.save())
        #expect(server.name == "Updated")
        #expect(server.baseURL == f.url("updated"))
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<OPDSServer>()) == 1)
        #expect(f.script.remaining == 0)
    }

    @Test func detailSelectsAcquisitionDownloadsImportsAndCallsBack() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        let cover = f.url("large-cover")
        let book = entry(f, types: ["application/pdf", "text/plain", "application/x-mobipocket-ebook"], cover: cover)
        f.script.enqueue(cover, data: coverData(), held: true)
        var added: [String] = []
        let hosted = try f.host(RemoteBookDetailView(server: server, entry: book) { added.append($0) })
        defer { hosted.close() }
        try await eventually { f.script.observed.count == 1 }
        #expect((f.detail.coverImage != nil) == false)
        let placeholder = try await hosted.signature()
        f.script.release()
        try await eventually { (f.detail.coverImage != nil) == true }
        #expect(try await hosted.signature() != placeholder)
        f.selectAcquisition(1)
        let downloadURL = book.acquisitions[1].url
        f.script.enqueue(downloadURL, data: Data("The downloaded text has real words.".utf8),
                         headers: ["Content-Disposition": "attachment; filename=Selected.txt"], held: true)
        let download = f.download
        let task = Task { await download() }
        try await eventually { f.script.observed.count == 2 }
        #expect(f.detail.downloading == true)
        #expect(added.isEmpty)
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<Book>()) == 0)
        let downloading = try await hosted.signature()
        f.script.release()
        await task.value
        #expect(f.detail.downloading == false)
        #expect(f.detail.downloadError == nil)
        #expect(added == ["Selected"])
        #expect(f.dismissCount == 1)
        let books = try f.container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.extractedText == "The downloaded text has real words.")
        #expect(books.first?.sourceFileName == "Selected.txt")
        #expect(books.first?.origin == BookOrigin(serverID: server.id, entryID: book.id, serverBookID: nil))
        #expect(books.first?.sourceDigest
            == KOReaderPartialMD5.digest(of: Data("The downloaded text has real words.".utf8)))
        #expect(try await hosted.signature() != downloading)
        #expect(f.script.observed.map(\.url) == [cover, downloadURL])
        #expect(f.script.remaining == 0)
    }

    @Test func detailDownloadFailuresLeaveLibraryUntouchedAndAllowRetry() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        let book = entry(f, types: ["application/pdf"])
        var added = false
        let hosted = try f.host(RemoteBookDetailView(server: server, entry: book) { _ in added = true })
        defer { hosted.close() }
        _ = try await hosted.signature()
        let initial = try await hosted.signature()
        let url = book.acquisitions[0].url
        let download = f.download
        f.script.enqueue(url, status: 403)
        await download()
        #expect(f.detail.downloadError == "Access denied (403). The user account may lack OPDS permission.")
        #expect(f.detail.downloading == false)
        #expect(try await hosted.signature() != initial)
        f.script.enqueue(url, data: Data("This is not a PDF".utf8))
        await download()
        #expect(f.detail.downloadError?.contains("Couldn't extract text") == true)
        f.script.fail(url)
        await download()
        #expect(f.detail.downloadError?.contains("Network error") == true)
        #expect(f.detail.downloading == false)
        #expect(added == false)
        #expect(f.dismissCount == 0)
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(f.script.observed.count == 3)
        #expect(f.script.remaining == 0)
    }

    @Test func unavailableAndAbsentFormatsRenderDifferentExplanationsAndDoNotDownload() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        var added = false
        let none = try f.host(RemoteBookDetailView(server: server, entry: entry(f, types: [])) { _ in added = true })
        let empty = try await none.signature()
        await f.download()
        #expect(f.script.observed.isEmpty)
        none.close()
        let unsupported = try f.host(RemoteBookDetailView(server: server,
            entry: entry(f, types: ["application/x-mobipocket-ebook", "application/vnd.amazon.ebook"])) { _ in added = true })
        defer { unsupported.close() }
        #expect(try await unsupported.signature() != empty)
        await f.download()
        #expect(f.script.observed.isEmpty)
        #expect(added == false)
        #expect(f.dismissCount == 0)
        #expect(try f.container.mainContext.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func detailCoverCacheThumbnailInvalidBytesAndFailureAreNonfatal() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        let cachedURL = f.url("cached")
        OPDSCoverCache.shared.store(Image(uiImage: UIImage(data: coverData())!), for: cachedURL)
        let cached = try f.host(RemoteBookDetailView(server: server,
            entry: entry(f, types: [], thumbnail: cachedURL)) { _ in Issue.record("Unexpected import") })
        try await eventually { (f.detail.coverImage != nil) == true }
        let cachedPixels = try await cached.signature()
        #expect(f.script.observed.isEmpty)
        cached.close()
        for transportFailure in [false, true] {
            let url = f.url(transportFailure ? "failed-cover" : "invalid-cover")
            if transportFailure { f.script.fail(url) }
            else { f.script.enqueue(url, data: Data("not an image".utf8)) }
            let hosted = try f.host(RemoteBookDetailView(server: server,
                entry: entry(f, types: [], cover: url)) { _ in Issue.record("Unexpected import") })
            let pixels = try await hosted.signature()
            #expect(pixels != cachedPixels)
            #expect((f.detail.coverImage != nil) == false)
            #expect(f.detail.downloadError == nil)
            #expect(f.script.observed.last?.url == url)
            hosted.close()
        }
        #expect(f.script.remaining == 0)
    }

    @Test func rowUsesThumbnailThenCoverAndRendersMetadataAndMissingCover() async throws {
        let f = try Fixture()
        defer { f.close() }
        let cover = f.url("row-cover")
        let thumb = f.url("row-thumb")
        var requested: [URL] = []
        let plain = try f.host(OPDSEntryRowView(entry: entry(f, types: [], metadata: false)) { url in
            requested.append(url)
            return nil
        })
        let plainPixels = try await plain.signature()
        #expect(requested.isEmpty)
        plain.close()
        let illustrated = try f.host(OPDSEntryRowView(entry: entry(f,
            types: ["text/plain", "application/x-mobipocket-ebook"], cover: cover, thumbnail: thumb)) { url in
            requested.append(url)
            return Image(uiImage: UIImage(data: coverData())!)
        })
        let illustratedPixels = try await illustrated.signature()
        #expect(requested == [thumb])
        #expect(illustratedPixels != plainPixels)
        illustrated.close()
        let failed = try f.host(OPDSEntryRowView(entry: entry(f, types: [], cover: cover)) { url in
            requested.append(url)
            return nil
        })
        defer { failed.close() }
        #expect(try await failed.signature() != illustratedPixels)
        #expect(requested == [thumb, cover])
    }

    @Test func defaultClientFactoryKeepsTheSharedSession() async {
        let client = EnvironmentValues().opdsClientFactory()
        let defaultSession = await client.session
        #expect(defaultSession === URLSession.shared)
    }

    @Test func navigationOnlyFeedRendersCategoriesWithoutDownloading() async throws {
        let f = try Fixture()
        defer { f.close() }
        _ = f.server()
        f.script.enqueue(f.base, data: atom(categories: ["Authors", "Recent additions"]))
        let hosted = try f.host(BrowseServerView(session: f.browse))
        defer { hosted.close() }
        try await eventually { f.browse.displayEntries.count == 2 }
        #expect(f.browse.displayEntries.map(\.title) == ["Authors", "Recent additions"])
        #expect(f.browse.displayEntries.allSatisfy { $0.navigationLink != nil && $0.acquisitions.isEmpty })
        let categories = try await hosted.signature()
        f.script.enqueue(f.base, data: atom(categories: ["Different category"]))
        await f.reload()
        #expect(f.browse.displayEntries.map(\.title) == ["Different category"])
        #expect(try await hosted.signature() != categories)
        #expect(f.script.observed.map(\.url) == [f.base, f.base])
        #expect(f.script.remaining == 0)
    }

    // Mutations: ignoring captured navigation targets or next links prevents the session
    // from requesting the advertised URL; dropping metadata leaves both surfaces empty.
    @Test func capturedNavigationPaginationAndMetadataSurfaces() async throws {
        let f = try Fixture()
        defer { f.close() }
        let server = f.server()
        f.script.enqueue(f.base, data: try OPDSCapturedFixture.data("cwng-root-2026-09-07"))
        await f.reload()
        let sections = OPDSBrowseLogic.sections(for: f.browse.displayEntries)
        #expect(sections.navigation.count == 17)
        let recent = try #require(sections.navigation.first { $0.title == "Recently added Books" }?.navigationLink)
        f.script.enqueue(recent, data: try OPDSCapturedFixture.data("cwng-new"))
        await f.browse.load(url: recent, on: server, modelContext: f.container.mainContext, makeClient: f.client)
        #expect(f.browse.displayEntries.count == 60)
        let next = try #require(f.browse.nextPageURL)
        #expect(next.path == "/opds/new" && next.query == "offset=60")
        // A captured terminal feed is a hermetic response, not a claim about the live second page.
        f.script.enqueue(next, data: try OPDSCapturedFixture.data("cwng-acquisition-hot"))
        await f.more()
        #expect(f.browse.displayEntries.count == 102)
        #expect(f.browse.nextPageURL == nil)
        await f.more()
        #expect(f.script.observed.map(\.url) == [f.base, recent, next])
        let book = try #require(f.browse.displayEntries.dropFirst(60).first)
        #expect(OPDSMetadataLogic.discoveryFields(for: book).last?.value == "Project Gutenberg")
        let row = try f.host(OPDSEntryRowView(entry: book, coverProvider: { _ in Image(systemName: "book.closed") }))
        #expect(Set(try await row.signature()).count > 8)
        try row.saveJPEG("leg32-browse-row")
        row.close()
        let cover = try #require(book.coverURL)
        f.script.enqueue(cover, data: coverData())
        let detail = try f.host(RemoteBookDetailView(server: server, entry: book, onAdded: { _ in }))
        defer { detail.close() }
        try await eventually { f.detail.coverImage != nil }
        #expect(Set(try await detail.signature()).count > 8)
        #expect(OPDSMetadataLogic.detailFields(for: book).last?.value == "ENG")
        try detail.saveJPEG("leg32-book-detail")
        #expect(f.script.remaining == 0)
    }

    @Test func scriptConsumesDistinctAndRepeatedStubsWithoutReuse() async throws {
        let f = try Fixture()
        defer { f.close() }
        let other = f.url("other")
        f.script.enqueue(f.base, data: Data("first".utf8))
        f.script.enqueue(other, data: Data("other".utf8))
        f.script.enqueue(f.base, data: Data("second".utf8))
        let (first, _) = try await f.session.data(from: f.base)
        let (second, _) = try await f.session.data(from: f.base)
        let (third, _) = try await f.session.data(from: other)
        #expect(String(decoding: first, as: UTF8.self) == "first")
        #expect(String(decoding: second, as: UTF8.self) == "second")
        #expect(String(decoding: third, as: UTF8.self) == "other")
        #expect(f.script.remaining == 0)
        #expect(f.script.observed.map(\.url) == [f.base, f.base, other])
        // Explicit crash controls run separately from the green lane, using the same suite.
        if let mode = ProcessInfo.processInfo.environment["SPEEDREAD_MOCK_SCRIPT_POSITIVE_CONTROL"] {
            _ = try await f.session.data(from: mode == "exhausted" ? f.base : f.url("unstubbed"))
            Issue.record("An exhausted or unmatched script returned instead of trapping")
        }
        #expect(f.script.remaining == 0)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let browse = BrowseServerSession()
        let editor = ServerEditSession()
        var detail = RemoteBookDetailSession()
        var activeServer: OPDSServer?
        var detailEntry: OPDSEntry?
        var detailAdded: (String) -> Void = { _ in }
        var dismissCount = 0
        let script = MockRequestScript()
        let session: URLSession
        let base: URL
        let theme: ThemeManager
        let defaultsName = "opds-surface-" + UUID().uuidString

        init() throws {
            base = URL(string: "https://opds-fixture.invalid")!.appendingPathComponent(UUID().uuidString)
            container = try ModelContainer(for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            session = mockSession(script: script)
            theme = ThemeManager(defaults: UserDefaults(suiteName: defaultsName)!)
        }
        func url(_ path: String) -> URL { base.appendingPathComponent(path) }
        func server(_ name: String = "Catalog", path: String? = nil) -> OPDSServer {
            let server = OPDSServer(name: name, baseURL: path.map(url) ?? base, username: "")
            container.mainContext.insert(server)
            activeServer = server
            return server
        }
        func host(_ view: RemoteBookDetailView) throws -> Hosted {
            detail = RemoteBookDetailSession()
            detailEntry = view.entry
            detailAdded = view.onAdded
            return try hostRoot(RemoteBookDetailView(server: view.server, entry: view.entry,
                onAdded: view.onAdded, session: detail))
        }
        func host<V: View>(_ view: V) throws -> Hosted { try hostRoot(view) }
        private func hostRoot<V: View>(_ view: V) throws -> Hosted {
            let client = OPDSClient(session: session)
            return try Hosted(view.modelContainer(container).environment(theme)
                .environment(\.opdsClientFactory, { client }))
        }
        func client() -> OPDSClient { OPDSClient(session: session) }
        func select(_ id: UUID) {
            let servers = try! container.mainContext.fetch(FetchDescriptor<OPDSServer>())
            browse.selectServer(id, servers: servers, modelContext: container.mainContext)
        }
        func reload() async {
            await browse.load(url: base, on: activeServer!, modelContext: container.mainContext, makeClient: client)
        }
        func more() async { await browse.loadMore(on: activeServer!, makeClient: client) }
        func search(_ query: String) async {
            browse.searchText = query
            await browse.runSearch(on: activeServer!, makeClient: client)
        }
        func edit(_ name: String, _ url: String, _ insecure: Bool) {
            editor.name = name
            editor.urlString = url
            editor.allowInsecureHTTP = insecure
        }
        func save() -> Bool { editor.save(server: activeServer, modelContext: container.mainContext) }
        func probeConnection() async { await editor.testConnection(server: activeServer, makeClient: client) }
        func selectAcquisition(_ index: Int) { detail.selectedAcquisitionIndex = index }
        func download() async {
            await detail.performDownload(entry: detailEntry!, on: activeServer!,
                modelContext: container.mainContext, makeClient: client, onAdded: detailAdded, dismiss: { self.dismissCount += 1 })
        }
        func close() {
            session.invalidateAndCancel()
            script.close()
            UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        }
    }

    @MainActor
    private final class Hosted {
        let window: UIWindow
        let view: UIView
        init<V: View>(_ root: V) throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 1000)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            view = host.view
            view.frame = window.bounds
            view.layoutIfNeeded()
        }
        func submitSearch(_ query: String) async throws {
            func find(_ controller: UIViewController) -> UISearchController? {
                if let search = controller.navigationItem.searchController { return search }
                for child in controller.children {
                    if let bar = find(child) { return bar }
                }
                return nil
            }
            let root = try #require(window.rootViewController)
            let search = try #require(find(root), "SwiftUI must install its searchable control")
            search.isActive = true
            let bar = search.searchBar
            let delegate = try #require(bar.delegate)
            bar.text = query
            delegate.searchBar?(bar, textDidChange: query)
            search.searchResultsUpdater?.updateSearchResults(for: search)
            // Let SwiftUI install the changed binding before its submit closure reads it.
            try await Task.sleep(for: .milliseconds(100))
            let field = bar.searchTextField
            let submitEvents: [UIControl.Event] = [.primaryActionTriggered, .editingDidEndOnExit]
            let submitEvent = try #require(submitEvents.first { event in
                field.allTargets.contains { target in
                    !(field.actions(forTarget: target, forControlEvent: event) ?? []).isEmpty
                }
            }, "The installed search field must register a submit action")
            field.sendActions(for: submitEvent)
        }
        func close() { window.isHidden = true; window.rootViewController = nil }
        func saveJPEG(_ name: String) throws {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image {
                view.layer.render(in: $0.cgContext)
            }
            let jpeg = try #require(image.jpegData(compressionQuality: 0.35))
            try jpeg.write(to: URL(fileURLWithPath: "/tmp/\(name).jpg"))
        }
        func signature() async throws -> [UInt32] {
            try await Task.sleep(for: .milliseconds(300))
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image {
                view.layer.render(in: $0.cgContext)
            }
            let cg = try #require(image.cgImage)
            let data = try #require(cg.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            #expect(cg.bitsPerPixel == 32)
            var samples: [UInt32] = []
            for y in stride(from: 110, to: cg.height - 40, by: 3) {
                for x in stride(from: 12, to: cg.width - 12, by: 3) {
                    let offset = y * cg.bytesPerRow + x * 4
                    samples.append(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
                }
            }
            return samples
        }
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(predicate(), "Hosted view did not reach the expected state")
    }

    private func atom(books: [String] = [], next: URL? = nil, cover: URL? = nil, categories: [String] = []) -> Data {
        let entries = books.map { title in
            """
            <entry><id>\(title)</id><title>\(title)</title><author><name>Fixture author</name></author>
            <link rel="http://opds-spec.org/acquisition" href="book.txt" type="text/plain"/>
            \(cover.map { "<link rel=\"http://opds-spec.org/image/thumbnail\" href=\"\($0.absoluteString)\"/>" } ?? "")
            </entry>
            """
        }.joined()
        let navigation = categories.map { title in
            "<entry><id>\(title)</id><title>\(title)</title><link href=\"category\" type=\"application/atom+xml;profile=opds-catalog\"/></entry>"
        }.joined()
        return Data("""
        <feed xmlns="http://www.w3.org/2005/Atom"><id>fixture</id><title>Catalog</title>
        \(next.map { "<link rel=\"next\" href=\"\($0.absoluteString)\"/>" } ?? "")
        \(entries)\(navigation)</feed>
        """.utf8)
    }

    private func entry(_ f: Fixture, types: [String], cover: URL? = nil,
                       thumbnail: URL? = nil, metadata: Bool = true) -> OPDSEntry {
        OPDSEntry(id: UUID().uuidString, title: "Remote title", authors: metadata ? ["First author", "Second author"] : [],
            summary: metadata ? "A detailed summary of this remote book." : nil, updated: nil, published: nil,
            language: metadata ? "en" : nil, coverURL: cover, thumbnailURL: thumbnail, navigationLink: nil,
            acquisitions: types.enumerated().map {
                OPDSAcquisition(url: f.url("format\($0.offset)"), mimeType: $0.element, length: nil, title: nil)
            })
    }

    private func coverData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }.jpegData(compressionQuality: 0.5)!
    }
}
