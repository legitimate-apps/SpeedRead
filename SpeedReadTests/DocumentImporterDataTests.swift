import Testing
import Foundation
import SwiftData
import UIKit
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
@MainActor
struct DocumentImporterDataTests {

    /// `defaultTitle` stripped the extension with
    /// `filename.replacingOccurrences(of: ".\(ext)")` where `ext` had already been lowercased,
    /// so a server sending "Dracula.TXT" matched nothing and the extension stayed in the book's
    /// title. Servers do send uppercase extensions; the routing already handled them, only the
    /// title derivation did not.
    @Test func anUppercaseExtensionIsStrippedFromTheDerivedTitle() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        // No "Title:" header, so the importer must fall back to deriving from the filename.
        let data = Data("Just some body text with no title header at all.".utf8)

        let book = try importer.importData(data, filename: "Dracula.TXT")

        #expect(book.title == "Dracula")
        #expect(book.title.lowercased().contains(".txt") == false)
    }

    @Test func importsPlainTextFromData() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let text = "Title: My Story\n\nOnce upon a time there was a tiny test."
        let data = Data(text.utf8)
        let book = try importer.importData(data, filename: "story.txt")
        #expect(book.wordCount > 0)
        #expect(book.sourceFileName == "story.txt")
        #expect(book.extractedText.contains("Once upon"))
        #expect(book.chapters.isEmpty)
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

    @Test func importRecordsTheKOReaderDigestOfTheImportedBytes() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let url = try #require(Bundle.main.url(forResource: "TheMetamorphosis", withExtension: "epub"))

        let book = try importer.importData(try Data(contentsOf: url), filename: "TheMetamorphosis.epub")

        // Oracle from a sync server's own implementation, run over this exact file.
        #expect(book.sourceDigest == "cd4aad201fc3bba1606d427e4bd9a8e8")
        #expect(book.origin == nil)
    }

    @Test func aDownloadRecordsWhereTheBookCameFrom() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let origin = BookOrigin(serverID: UUID(), entryID: "urn:uuid:2853dacf-ed79-42f5-8e8a-a7bb3d1ae6a2",
                                serverBookID: "100")

        let book = try importer.importData(Data("Some downloaded words.".utf8), filename: "d.txt",
                                           origin: origin)

        #expect(book.origin == origin)
        #expect(book.sourceDigest != nil)
    }

    @Test func wordCountMatchesTokenization() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let text = "one two three four five six seven eight nine ten"
        let book = try importer.importData(Data(text.utf8), filename: "ten.txt")
        #expect(book.wordCount == Book.tokenize(book.extractedText).count)
    }

    /// A scan: every page is a picture, so PDFKit finds no text. This imported as a 0-word book
    /// with no error until 1.4 (13); 26 of 117 PDFs on the developer's Mac had no text layer.
    @Test func aPDFWithOnlyPicturesIsRefusedAndNothingIsSaved() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        let scan = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { pdf in
            for shade in [0.2, 0.6] {
                pdf.beginPage()
                UIColor(white: shade, alpha: 1).setFill()
                UIRectFill(CGRect(x: 72, y: 72, width: 468, height: 648))
            }
        }

        #expect(throws: ExtractionError.noReadableText(.pdf)) {
            try importer.importData(scan, filename: "Scanned.pdf")
        }
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
    }

    @Test func aTextFileOfOnlyWhitespaceIsRefusedAsHavingNoText() throws {
        let context = try inMemoryContext()
        let importer = DocumentImporter(modelContext: context)
        #expect(throws: ExtractionError.noReadableText(.plainText)) {
            try importer.importData(Data("  \n\t \n".utf8), filename: "blank.txt")
        }
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
    }
}
