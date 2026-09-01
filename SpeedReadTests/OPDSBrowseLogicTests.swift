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

    @Test func searchFallsBackToNormalizedServerPathAndCanBeUnavailable() {
        #expect(OPDSBrowseLogic.searchAction(
            query: "swift",
            advertisedTemplate: nil,
            baseURL: URL(string: "https://books.example/opds///")
        ) == .fetch(URL(string: "https://books.example/opds/opds/search/swift")!))

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
