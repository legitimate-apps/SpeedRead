import SwiftUI
import Testing
@testable import SpeedRead

@Suite("OPDS cover cache")
@MainActor
struct OPDSCoverCacheTests {
    @Test func shippingCapacityEvictsOnlyTheOldestOfTwoHundredAndOneCovers() throws {
        let cache = OPDSCoverCache()
        let urls = try (0...200).map { index in
            try #require(URL(string: "https://covers.example/\(index).jpg"))
        }

        for url in urls {
            cache.store(Image(systemName: "book.closed"), for: url)
        }

        #expect(cache.image(for: urls[0]) == nil)
        #expect(cache.image(for: urls[1]) != nil)
        #expect(cache.image(for: urls[200]) != nil)
    }

    @Test func replacingAnExistingCoverDoesNotRefreshItsInsertionAge() throws {
        let cache = OPDSCoverCache(softCap: 2)
        let first = try #require(URL(string: "https://covers.example/first.jpg"))
        let second = try #require(URL(string: "https://covers.example/second.jpg"))
        let third = try #require(URL(string: "https://covers.example/third.jpg"))

        cache.store(Image(systemName: "1.circle"), for: first)
        cache.store(Image(systemName: "2.circle"), for: second)
        cache.store(Image(systemName: "1.circle.fill"), for: first)
        cache.store(Image(systemName: "3.circle"), for: third)

        #expect(cache.image(for: first) == nil)
        #expect(cache.image(for: second) != nil)
        #expect(cache.image(for: third) != nil)
    }

    @Test func fullURLIsTheCacheKeyIncludingItsQuery() throws {
        let cache = OPDSCoverCache(softCap: 2)
        let small = try #require(URL(string: "https://covers.example/book.jpg?size=small"))
        let large = try #require(URL(string: "https://covers.example/book.jpg?size=large"))

        cache.store(Image(systemName: "photo"), for: small)

        #expect(cache.image(for: small) != nil)
        #expect(cache.image(for: large) == nil)
    }

    @Test func aCoverOutlivesTheCacheThatKeptIt() throws {
        let directory = try Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://covers.example/kept.jpg"))

        #expect(OPDSCoverCache(directory: directory).store(data: OPDSCoverLogicTests.png(width: 1_200, height: 1_800), for: url) != nil)

        let file = directory.appendingPathComponent(OPDSCoverLogic.fileName(for: url))
        #expect(OPDSCoverLogicTests.pixelSize(try Data(contentsOf: file)) == CGSize(width: 560, height: 840))
        #expect(OPDSCoverCache(directory: directory).image(for: url) != nil)
    }

    @Test func theDiskKeepsOnlyTheNewestCovers() throws {
        let directory = try Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = OPDSCoverCache(directory: directory, diskCap: 2)
        let urls = try (0..<3).map { try #require(URL(string: "https://covers.example/\($0).jpg")) }

        for url in urls {
            _ = cache.store(data: OPDSCoverLogicTests.png(width: 40, height: 60), for: url)
        }

        let later = OPDSCoverCache(directory: directory)
        #expect(later.image(for: urls[0]) == nil)
        #expect(later.image(for: urls[1]) != nil)
        #expect(later.image(for: urls[2]) != nil)
    }

    @Test func bytesThatAreNoImageAreNotKept() throws {
        let directory = try Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://covers.example/broken.jpg"))

        #expect(OPDSCoverCache(directory: directory).store(data: Data("nope".utf8), for: url) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private static func emptyDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("covers-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
