import Foundation
import SwiftData
import Testing
@testable import SpeedRead

@Suite("Sample book loader")
@MainActor
struct SampleBookLoaderTests {
    @Test func emptyStoreLoadsTheEntireBundledCatalogWithCanonicalMetadata() throws {
        let context = try makeContext()

        SampleBookLoader(modelContext: context).loadSampleBooksIfNeeded()

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        #expect(Set(books.map(\.sourceFileName)) == [
            "TheYellowWallpaper.epub",
            "TheMetamorphosis.epub",
            "AChristmasCarol.epub",
            "AChristmasCarol.pdf"
        ])
        #expect(books.filter { $0.title == "A Christmas Carol" }.count == 2)
        #expect(books.allSatisfy { !$0.words.isEmpty })
        #expect(books.first { $0.sourceFileName == "TheYellowWallpaper.epub" }?.author
            == "Charlotte Perkins Gilman")
    }

    @Test func existingStoreReturnsBeforeConsultingBundledResources() throws {
        let context = try makeContext()
        context.insert(Book(
            title: "Existing",
            author: "Author",
            extractedText: "already here",
            sourceFileName: "existing.txt"
        ))
        try context.save()
        let resources = RecordingSampleResources(payloads: [:])

        SampleBookLoader(
            modelContext: context,
            resources: resources
        ).loadSampleBooksIfNeeded()

        #expect(resources.requests.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
    }

    @Test func missingAndMalformedSamplesAreSkippedWithoutDiscardingValidOnes() throws {
        let context = try makeContext()
        let yellowURL = try #require(Bundle.main.url(
            forResource: "TheYellowWallpaper",
            withExtension: "epub"
        ))
        let resources = RecordingSampleResources(payloads: [
            "TheYellowWallpaper.epub": try Data(contentsOf: yellowURL),
            "TheMetamorphosis.epub": Data("not an epub".utf8)
        ])

        SampleBookLoader(
            modelContext: context,
            resources: resources
        ).loadSampleBooksIfNeeded()

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(resources.requests == [
            "TheYellowWallpaper.epub",
            "TheMetamorphosis.epub",
            "AChristmasCarol.epub",
            "AChristmasCarol.pdf"
        ])
        #expect(books.map(\.sourceFileName) == ["TheYellowWallpaper.epub"])
        #expect(books[0].wordCount == 9_173)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}

@MainActor
private final class RecordingSampleResources: SampleBookResourceProviding {
    let payloads: [String: Data]
    private(set) var requests: [String] = []

    init(payloads: [String: Data]) {
        self.payloads = payloads
    }

    func data(named fileName: String) throws -> Data? {
        requests.append(fileName)
        return payloads[fileName]
    }
}
