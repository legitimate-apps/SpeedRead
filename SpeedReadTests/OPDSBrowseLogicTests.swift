import Foundation
import Testing
@testable import SpeedRead

@Suite("OPDS browse logic")
struct OPDSBrowseLogicTests {
    @Test func searchedEntriesReplacePaginationOnlyWhileSearchIsActive() {
        let paginated = [entry(id: "page", acquisitions: [acquisition()])]
        let searched = feed(entries: [entry(id: "search", acquisitions: [acquisition()])])

        #expect(OPDSBrowseLogic.displayEntries(
            searchText: "query",
            searchedFeed: searched,
            paginatedEntries: paginated
        ).map(\.id) == ["search"])
        #expect(OPDSBrowseLogic.displayEntries(
            searchText: "",
            searchedFeed: searched,
            paginatedEntries: paginated
        ).map(\.id) == ["page"])
        #expect(OPDSBrowseLogic.displayEntries(
            searchText: "query",
            searchedFeed: nil,
            paginatedEntries: paginated
        ).map(\.id) == ["page"])
    }

    @Test func sectionsSeparateNavigationFromAcquirableBooks() {
        let category = entry(
            id: "category",
            navigationLink: URL(string: "https://books.example/category")!
        )
        let book = entry(id: "book", acquisitions: [acquisition()])
        let acquirableNavigation = entry(
            id: "both",
            navigationLink: URL(string: "https://books.example/both")!,
            acquisitions: [acquisition()]
        )

        let sections = OPDSBrowseLogic.sections(for: [category, book, acquirableNavigation])

        #expect(sections.navigation.map(\.id) == ["category"])
        #expect(sections.books.map(\.id) == ["book", "both"])
    }

    @Test func searchActionTrimsEncodesAndPrefersAdvertisedTemplate() {
        #expect(OPDSBrowseLogic.searchAction(
            query: "   ",
            advertisedTemplate: "https://search.example/{searchTerms}",
            baseURL: URL(string: "https://fallback.example/opds/")
        ) == .clear)

        #expect(OPDSBrowseLogic.searchAction(
            query: " science fiction ",
            advertisedTemplate: "https://search.example/?q={searchTerms}",
            baseURL: URL(string: "https://fallback.example/opds/")
        ) == .fetch(URL(string: "https://search.example/?q=science%20fiction")!))
    }

    @Test func searchEncodesWithThePathCharacterSetNotTheQueryOne() {
        // The other encoding test uses a space, which BOTH .urlPathAllowed and .urlQueryAllowed
        // render as %20 -- so it passes identically under either set and pins nothing. A mutation
        // swapping the two survived the suite for exactly that reason.
        //
        // MEASURED: "?" is the discriminator. .urlPathAllowed -> %3F, .urlQueryAllowed -> literal
        // "?". Leaving it literal would end the path and silently truncate the search term into a
        // second query component, so this is a real behavioural difference, not a formatting one.
        #expect(OPDSBrowseLogic.searchAction(
            query: "who goes there?",
            advertisedTemplate: "https://search.example/{searchTerms}",
            baseURL: nil
        ) == .fetch(URL(string: "https://search.example/who%20goes%20there%3F")!))
    }

    /// CWNG decodes the search term with `unquote_plus` (OBSERVED on v4.1.63: `/opds/search/C++`
    /// searched "C"; `/opds/search/C%2B%2B` searched "C++"). So `+` and every other reserved
    /// character a server might read as syntax is escaped, in a path template and a query one.
    @Test("a search term reaches the server as typed", arguments: [
        ("https://books.example/opds/search/{searchTerms}", "C++", "https://books.example/opds/search/C%2B%2B"),
        ("https://books.example/opds/search?query={searchTerms}", "C++ & Rust=fun",
         "https://books.example/opds/search?query=C%2B%2B%20%26%20Rust%3Dfun"),
        ("https://books.example/opds/search/{searchTerms}", "AC/DC #1", "https://books.example/opds/search/AC%2FDC%20%231"),
        ("https://books.example/opds/search/{searchTerms}", "caf\u{E9}", "https://books.example/opds/search/caf%C3%A9"),
    ])
    func aSearchTermReachesTheServerAsTyped(template: String, query: String, expected: String) {
        #expect(OPDSBrowseLogic.searchAction(query: query, advertisedTemplate: template, baseURL: nil)
            == .fetch(URL(string: expected)!))
    }

    @Test func searchFallsBackToNormalizedServerPathAndCanBeUnavailable() {
        #expect(OPDSBrowseLogic.searchAction(
            query: "swift",
            advertisedTemplate: nil,
            baseURL: URL(string: "https://books.example/opds///")
        ) == .fetch(URL(string: "https://books.example/opds/search/swift")!))

        #expect(OPDSBrowseLogic.searchAction(
            query: "swift",
            advertisedTemplate: nil,
            baseURL: nil
        ) == .unavailable)
    }

    private func feed(entries: [OPDSEntry]) -> OPDSFeed {
        OPDSFeed(
            title: "Feed", id: "feed", updated: nil, entries: entries,
            navigationLinks: [], nextPageURL: nil,
            searchDescriptionURL: nil, searchTemplate: nil
        )
    }

    private func entry(
        id: String,
        navigationLink: URL? = nil,
        acquisitions: [OPDSAcquisition] = []
    ) -> OPDSEntry {
        OPDSEntry(
            id: id, title: id, authors: [], summary: nil,
            updated: nil, published: nil, language: nil,
            coverURL: nil, thumbnailURL: nil,
            navigationLink: navigationLink, acquisitions: acquisitions
        )
    }

    private func acquisition() -> OPDSAcquisition {
        OPDSAcquisition(
            url: URL(string: "https://books.example/book.epub")!,
            mimeType: "application/epub+zip",
            length: nil,
            title: nil
        )
    }
}
