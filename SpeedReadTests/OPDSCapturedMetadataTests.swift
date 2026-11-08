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

    /// CWNG's feed.xml carries `calibre:series`, `calibre:series_index` and `dcterms:isPartOf` for a
    /// book in a series. Captured from a real CWNG catalog: four of its sixty books are in one.
    @Test func capturedSeriesAreNotDropped() throws {
        let feed = try parse("cwng-new")
        let series = feed.entries.compactMap { entry in entry.series.map { (entry.title, $0) } }
        #expect(series.map(\.0) == ["2001: A Space Odyssey", "Neuromancer", "Less : A Novel",
                                     "All the Light We Cannot See(elib.cc)"])
        #expect(series.map(\.1) == [
            OPDSSeries(name: "Space Odyssey", index: 1), OPDSSeries(name: "Neuromancer", index: 1),
            OPDSSeries(name: "Less", index: 1), OPDSSeries(name: "Pulitzer Prize Winner", index: 2015),
        ])
        #expect(feed.entries.first?.series == nil)
    }

    /// The template's current shape: an escaped name, a two-place index, and the Dublin Core
    /// fallback alone for a feed that has only that.
    @Test func seriesNamesIndexesAndTheDublinCoreFallback() throws {
        let feed = try OPDSAtomParser(baseURL: base).parse(data: Data("""
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:calibre="http://calibre.kovidgoyal.net/2009/metadata">
        <entry><title>Abaddon's Gate</title><calibre:series>Leviathan &amp; Co</calibre:series>
        <calibre:series_index>3.00</calibre:series_index><dcterms:isPartOf>Leviathan &amp; Co</dcterms:isPartOf></entry>
        <entry><title>Between</title><calibre:series>Leviathan</calibre:series><calibre:series_index>2.50</calibre:series_index></entry>
        <entry><title>Generic</title><dcterms:isPartOf>Earthsea</dcterms:isPartOf></entry>
        <entry><title>Unnumbered</title><calibre:series>Discworld</calibre:series><calibre:series_index></calibre:series_index></entry>
        <entry><title>Alone</title><calibre:series>  </calibre:series></entry>
        </feed>
        """.utf8))
        #expect(feed.entries.map(\.series) == [
            OPDSSeries(name: "Leviathan & Co", index: 3), OPDSSeries(name: "Leviathan", index: 2.5),
            OPDSSeries(name: "Earthsea", index: nil), OPDSSeries(name: "Discworld", index: nil), nil,
        ])
    }

    private func parse(_ name: String) throws -> OPDSFeed {
        try OPDSAtomParser(baseURL: base).parse(data: OPDSCapturedFixture.data(name))
    }
}
