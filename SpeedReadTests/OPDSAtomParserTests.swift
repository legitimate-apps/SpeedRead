import Testing
import Foundation
@testable import SpeedRead

private final class _FixtureAnchor {}

enum OPDSCapturedFixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: _FixtureAnchor.self)
        if let url = bundle.url(forResource: name, withExtension: "xml") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures/OPDS") {
            return try Data(contentsOf: url)
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OPDS")
            .appendingPathComponent("\(name).xml")
        return try Data(contentsOf: sourceURL)
    }
}

private let testBase = URL(string: "https://books.example.com/")!

@Suite("OPDS Atom Parser")
struct OPDSAtomParserTests {

    // Mutations: lost navigation or search links break the captured response assertions.
    @Test func parsesRootNavigationFeed() throws {
        let data = try OPDSCapturedFixture.data("cwng-root")
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: data)

        #expect(feed.title == "Calibre-Web NextGen")
        #expect(feed.entries.count >= 3)
        #expect(feed.entries.contains { $0.title.contains("Alphabetical") })
        #expect(feed.entries.contains { $0.title.contains("Recently added") })

        let recentEntry = feed.entries.first { $0.title.contains("Recently added") }
        #expect(recentEntry?.navigationLink?.absoluteString == "https://books.example.com/opds/new")
        #expect(recentEntry?.acquisitions.isEmpty == true)

        #expect(feed.searchTemplate != nil)
        #expect(feed.searchTemplate?.contains("{searchTerms}") == true)
        #expect(feed.searchDescriptionURL?.absoluteString == "https://books.example.com/opds/osd")
    }

    // Mutations: lost acquisition, cover, or advertised next links break the captured response assertions.
    @Test func parsesAcquisitionFeedWithBooks() throws {
        let data = try OPDSCapturedFixture.data("cwng-new")
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: data)

        #expect(!feed.entries.isEmpty)

        let bookEntries = feed.entries.filter { !$0.acquisitions.isEmpty }
        #expect(!bookEntries.isEmpty)

        guard let firstBook = bookEntries.first else {
            Issue.record("No acquisition entries found in fixture")
            return
        }
        #expect(!firstBook.title.isEmpty)
        #expect(firstBook.id.hasPrefix("urn:uuid:"))
        #expect(!firstBook.authors.isEmpty)

        let acquisition = firstBook.acquisitions.first
        #expect(acquisition?.mimeType == "application/epub+zip")
        #expect(acquisition?.url.absoluteString.contains("/opds/download/") == true)
        #expect((acquisition?.length ?? 0) > 0)
        #expect(acquisition?.displayFormat == "EPUB")

        #expect(firstBook.coverURL?.absoluteString.contains("/opds/cover/") == true)
        #expect(firstBook.thumbnailURL?.absoluteString.contains("/opds/cover/") == true)

        #expect(feed.nextPageURL?.absoluteString.contains("/opds/new") == true)
        #expect(feed.nextPageURL?.absoluteString.contains("offset=60") == true)
    }

    // Mutations: dropped search acquisitions break the captured response assertions.
    @Test func parsesSearchResultsFeed() throws {
        let data = try OPDSCapturedFixture.data("cwng-search")
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: data)

        #expect(!feed.entries.isEmpty)
        let booksWithAcquisitions = feed.entries.filter { !$0.acquisitions.isEmpty }
        #expect(!booksWithAcquisitions.isEmpty)
    }

    @Test func resolvesAbsoluteAndRelativeHrefs() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Mixed URLs</title>
            <id>urn:test:mixed</id>
            <link rel="next" href="/opds/new?offset=60"/>
            <entry>
                <title>Absolute Book</title>
                <id>urn:uuid:abc</id>
                <author><name>Some Author</name></author>
                <link rel="http://opds-spec.org/acquisition"
                      type="application/epub+zip"
                      href="https://other.example.com/files/book.epub"/>
                <link rel="http://opds-spec.org/image"
                      type="image/jpeg"
                      href="/covers/abc.jpg"/>
            </entry>
        </feed>
        """
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: Data(xml.utf8))

        let entry = feed.entries.first
        #expect(entry?.acquisitions.first?.url.absoluteString == "https://other.example.com/files/book.epub")
        #expect(entry?.coverURL?.absoluteString == "https://books.example.com/covers/abc.jpg")
        #expect(feed.nextPageURL?.absoluteString == "https://books.example.com/opds/new?offset=60")
    }

    @Test func handlesEntryWithoutCover() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>No Cover</title>
            <id>urn:test:no-cover</id>
            <entry>
                <title>Naked Book</title>
                <id>urn:uuid:naked</id>
                <author><name>Anonymous</name></author>
                <link rel="http://opds-spec.org/acquisition"
                      type="application/pdf"
                      href="/files/naked.pdf"/>
            </entry>
        </feed>
        """
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: Data(xml.utf8))

        let entry = feed.entries.first
        #expect(entry?.coverURL == nil)
        #expect(entry?.thumbnailURL == nil)
        #expect(entry?.acquisitions.first?.displayFormat == "PDF")
    }

    @Test func handlesEntryWithMultipleAcquisitionLinks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Multi-format</title>
            <id>urn:test:multi</id>
            <entry>
                <title>Available Everywhere</title>
                <id>urn:uuid:multi</id>
                <author><name>Author X</name></author>
                <link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="/d/1/epub"/>
                <link rel="http://opds-spec.org/acquisition" type="application/pdf" href="/d/1/pdf"/>
                <link rel="http://opds-spec.org/acquisition" type="text/plain" href="/d/1/txt"/>
            </entry>
        </feed>
        """
        let parser = OPDSAtomParser(baseURL: testBase)
        let feed = try parser.parse(data: Data(xml.utf8))

        let entry = feed.entries.first
        #expect(entry?.acquisitions.count == 3)
        let formats = entry?.acquisitions.map(\.displayFormat) ?? []
        #expect(formats.contains("EPUB"))
        #expect(formats.contains("PDF"))
        #expect(formats.contains("TXT"))
    }

    @Test func malformedXMLThrowsParseError() throws {
        let bad = Data("<feed><unclosed>".utf8)
        let parser = OPDSAtomParser(baseURL: testBase)
        do {
            _ = try parser.parse(data: bad)
            Issue.record("Expected parser to throw on malformed XML")
        } catch is OPDSParseError {
            // expected
        }
    }

    @Test func iso8601DateParserAcceptsBasicAndFractional() {
        let basic = OPDSAtomParser.parseDate("2026-05-19T23:57:02+00:00")
        let fractional = OPDSAtomParser.parseDate("2026-05-19T23:57:02.123+00:00")
        #expect(basic != nil)
        #expect(fractional != nil)
        #expect(OPDSAtomParser.parseDate("not a date") == nil)
    }

    @Test func concurrentDateParsingKeepsFormatsIndependent() async {
        let basic = OPDSAtomParser.parseDate("2026-05-19T23:57:02+00:00")
        let fractional = OPDSAtomParser.parseDate("2026-05-19T23:57:02.123+00:00")
        #expect(basic != nil)
        #expect(fractional != nil)
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    OPDSAtomParser.parseDate("2026-05-19T23:57:02+00:00") == basic
                        && OPDSAtomParser.parseDate("2026-05-19T23:57:02.123+00:00") == fractional
                        && OPDSAtomParser.parseDate("not a date") == nil
                }
            }
            for await matches in group { #expect(matches) }
        }
    }

}
