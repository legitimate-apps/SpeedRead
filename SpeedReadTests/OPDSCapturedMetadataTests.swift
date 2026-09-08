import Foundation
import Testing
@testable import SpeedRead

@Suite("Captured OPDS metadata")
struct OPDSCapturedMetadataTests {
    // Only resolves relative fixture links; this file never creates a network client.
    private let base = URL(fileURLWithPath: "/")

    // Mutations: dropping namespace normalization loses all 59 language values (B30).
    @Test func capturedLanguagesAreNotDropped() throws {
        let feed = try parse("cwng-new")
        #expect(feed.entries.count == 60)
        #expect(feed.entries.compactMap(\.language).count == 59)
        #expect(feed.entries.first?.language == "eng")
    }

    // Mutations: ignoring category attributes or nested publisher/name loses captured metadata.
    @Test func capturedCategoriesAndPublishers() throws {
        let feed = try parse("cwng-acquisition-hot")
        #expect(feed.entries.count == 42)
        #expect(feed.entries.flatMap(\.categories).count == 88)
        #expect(feed.entries.compactMap(\.publisher).count == 30)
        let book = try #require(feed.entries.first)
        #expect(book.publisher == "Project Gutenberg")
        #expect(book.categories.first?.term == "Copyists -- Fiction")
        #expect(book.categories.first?.label == "Copyists -- Fiction")
        #expect(book.categories.first?.scheme?.hasSuffix("bisac_subject/index.html") == true)
        #expect(book.categories.first?.displayName == "Copyists -- Fiction")
        #expect(book.language == "eng")
        #expect(book.authors == ["Herman Melville"])
    }

    // Mutations: hard-coded root sections, lost navigation hrefs, or book/navigation misclassification.
    @Test func bothRootsAndAlphabeticalNavigationStayServerDriven() throws {
        let old = OPDSBrowseLogic.sections(for: try parse("cwng-root").entries)
        let new = OPDSBrowseLogic.sections(for: try parse("cwng-root-2026-09-07").entries)
        #expect(old.navigation.count == 4)
        #expect(new.navigation.count == 17)
        #expect(old.books.isEmpty && new.books.isEmpty)
        #expect(Set(new.navigation.map(\.title)).subtracting(old.navigation.map(\.title)) == Set([
            "Hot Books", "Top Rated Books", "Discover", "Read Books", "Currently Reading",
            "Unread Books", "Authors", "Publishers", "Categories", "Series", "Languages",
            "Ratings", "File formats"
        ]))
        #expect(new.navigation.allSatisfy { $0.navigationLink != nil })
        let letters = OPDSBrowseLogic.sections(for: try parse("cwng-books-navigation").entries)
        #expect(letters.navigation.count == 28)
        #expect(letters.navigation.first?.title == "All")
        #expect(letters.books.isEmpty)
    }

    // Mutations: deleting next-link parsing breaks the real May acquisition feed;
    // inventing pages for terminal feeds breaks the remaining captures.
    @Test func capturedPaginationIsAdvertisedOnlyOnNew() throws {
        let next = try #require(parse("cwng-new").nextPageURL)
        #expect(next.path == "/opds/new")
        #expect(next.query == "offset=60")
        for name in ["cwng-root", "cwng-root-2026-09-07", "cwng-acquisition-hot",
                     "cwng-books-navigation", "cwng-search", "cwng-search-results"] {
            #expect(try parse(name).nextPageURL == nil)
        }
    }

    // Mutations: matching qualified names, losing parent text on child close, or treating
    // an HTML alternate as a catalogue destination corrupts generic OPDS entries.
    @Test func prefixesNestedTextAndNavigationLinkTypes() throws {
        let xml = """
        <a:feed xmlns:a="http://www.w3.org/2005/Atom" xmlns:d="http://purl.org/dc/terms/">
          <a:title>Library</a:title><a:entry><a:id>book</a:id><a:title>Book</a:title>
          <d:language>fr</d:language><d:publisher>Small Press</d:publisher>
          <a:summary>Before <b>middle</b> after</a:summary>
          <a:category term="fiction" label="Fiction"/>
          <a:link rel="subsection" type="application/atom+xml" href="/section"/>
          <a:link rel="alternate" type="text/html" href="/website"/>
          </a:entry><a:entry><a:id>empty</a:id><a:title>Empty</a:title></a:entry>
        </a:feed>
        """
        let feed = try OPDSAtomParser(baseURL: base).parse(data: Data(xml.utf8))
        let book = try #require(feed.entries.first)
        #expect(book.language == "fr")
        #expect(book.publisher == "Small Press")
        #expect(book.summary == "Before middle after")
        #expect(book.categories.map(\.displayName) == ["Fiction"])
        #expect(book.navigationLink?.path == "/section")
        #expect(feed.entries.last?.publisher == nil)
        #expect(feed.entries.last?.categories.isEmpty == true)
        #expect(feed.entries.last?.language == nil)
    }

    private func parse(_ name: String) throws -> OPDSFeed {
        try OPDSAtomParser(baseURL: base).parse(data: OPDSCapturedFixture.data(name))
    }
}
