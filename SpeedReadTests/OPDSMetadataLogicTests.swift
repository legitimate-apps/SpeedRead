import Foundation
import Testing
@testable import SpeedRead

struct OPDSMetadataLogicTests {
    // Mutations: hiding publisher/categories in either surface, displaying terms instead of
    // labels, or losing the B30 language value changes the fields users read.
    @Test func capturedMetadataReachesDiscoveryAndDetails() throws {
        let feed = try OPDSAtomParser(baseURL: URL(fileURLWithPath: "/")).parse(
            data: OPDSCapturedFixture.data("cwng-acquisition-hot"))
        let book = try #require(feed.entries.first)
        let discovery = OPDSMetadataLogic.discoveryFields(for: book)
        #expect(discovery.map(\.label) == ["Categories", "Publisher"])
        #expect(discovery.first?.value.contains("Copyists -- Fiction") == true)
        #expect(discovery.last?.text == "Publisher: Project Gutenberg")
        #expect(OPDSMetadataLogic.detailFields(for: book) == discovery + [
            .init(label: "Language", value: "ENG")
        ])
        #expect(Set(discovery.map(\.id)).count == discovery.count)
    }

    // Mutations: stale metadata leaking between entries, blank fields rendered, or missing term fallback.
    @Test func emptyMetadataAndCategoryFallback() throws {
        let feed = try OPDSAtomParser(baseURL: URL(fileURLWithPath: "/")).parse(data: Data("""
        <feed><entry><title>Book</title><category term="History" label=""/>
        <category term="Ignored"/><publisher>   </publisher><language> </language></entry>
        <entry><title>Empty</title></entry></feed>
        """.utf8))
        let book = try #require(feed.entries.first)
        #expect(OPDSMetadataLogic.discoveryFields(for: book) == [.init(label: "Categories", value: "History, Ignored")])
        let empty = try #require(feed.entries.last)
        #expect(OPDSMetadataLogic.discoveryFields(for: empty).isEmpty)
        #expect(OPDSMetadataLogic.detailFields(for: empty).isEmpty)
    }

    @Test("a series reads as the book's place in it", arguments: [
        (OPDSSeries(name: "The Expanse", index: 3), "Book 3 of The Expanse"),
        (OPDSSeries(name: "The Expanse", index: 2.5), "Book 2.5 of The Expanse"),
        (OPDSSeries(name: "Earthsea", index: nil), "Part of Earthsea"),
    ])
    func seriesText(series: OPDSSeries, expected: String) {
        #expect(OPDSMetadataLogic.seriesText(for: series) == expected)
    }
}
