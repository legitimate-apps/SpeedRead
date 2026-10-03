import Foundation
import Testing
@testable import SpeedRead

/// A sync server keys progress on a digest of the file it served. A book SpeedRead downloaded
/// before it recorded where the book came from can never be matched to that progress, so the
/// keys must be captured at download time, from the real wire shape.
@Suite("Book origin")
struct BookOriginTests {
    @Test func capturedCalibreWebAcquisitionsYieldTheirServerBookID() throws {
        let feed = try OPDSAtomParser(baseURL: URL(string: "https://library.example/opds")!).parse(
            data: OPDSCapturedFixture.data("cwng-acquisition-hot"))
        let entries = feed.entries.filter { !$0.acquisitions.isEmpty }
        #expect(!entries.isEmpty)
        for entry in entries {
            let ids = Set(entry.acquisitions.map { BookOrigin.serverBookID(fromAcquisition: $0.url) })
            // Every format of one entry names the same server book, and it is a number.
            #expect(ids.count == 1)
            let id = try #require(ids.first ?? nil)
            #expect(Int(id) != nil)
        }
    }

    @Test("server book id", arguments: [
        ("https://h.example/opds/download/100/epub/", "100"),
        ("https://h.example/calibre/opds/download/7/kepub", "7"),
        ("https://h.example/opds/download/abc/epub/", nil),
        ("https://h.example/get/epub/12/library", nil),
        ("https://h.example/opds/download/", nil),
    ] as [(String, String?)])
    func serverBookID(url: String, expected: String?) {
        #expect(BookOrigin.serverBookID(fromAcquisition: URL(string: url)!) == expected)
    }
}
