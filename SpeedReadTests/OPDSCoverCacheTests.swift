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
}
