import Testing
import Foundation
import SwiftData
@testable import SpeedRead

private func inMemoryContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
        configurations: config
    )
    return ModelContext(container)
}

@Suite("DocumentImporter.importData")
struct DocumentImporterDataTests {

    @Test func importsPlainTextFromData() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let text = "Title: My Story\n\nOnce upon a time there was a tiny test."
        let data = Data(text.utf8)
        let book = try importer.importData(data, filename: "story.txt")
        #expect(book.wordCount > 0)
        #expect(book.sourceFileName == "story.txt")
        #expect(book.extractedText.contains("Once upon"))
    }

    @Test func importsRTFFromData() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let rtf = "{\\rtf1\\ansi This is an RTF document for testing.}"
        let data = Data(rtf.utf8)
        let book = try importer.importData(data, filename: "doc.rtf")
        #expect(book.wordCount > 0)
        #expect(book.extractedText.contains("RTF document"))
    }

    @Test func unsupportedExtensionThrows() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let data = Data("garbage".utf8)
        #expect(throws: ExtractionError.unsupportedFormat) {
            _ = try importer.importData(data, filename: "thing.mobi")
        }
    }

    @Test func titleFallsBackToFilenameMinusExtension() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        // Body text with multiple lines so the text extractor's title heuristic
        // doesn't latch onto a single short opening line and override the
        // filename-based fallback.
        let body = """
        First paragraph that runs on for many words so the heuristics see real prose here.
        Second paragraph keeps going so nothing reads like a title.
        Third paragraph with even more words filling the page out properly.
        """
        let book = try importer.importData(
            Data(body.utf8),
            filename: "Untitled Manuscript.txt"
        )
        #expect(book.title == "Untitled Manuscript")
    }

    @Test func wordCountMatchesTokenization() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let text = "one two three four five six seven eight nine ten"
        let book = try importer.importData(Data(text.utf8), filename: "ten.txt")
        #expect(book.wordCount == Book.tokenize(book.extractedText).count)
    }
}
