//  DocumentImporter.swift
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct DocumentImporter {
    let modelContext: ModelContext

    func importFile(at url: URL) throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let extractor: TextExtractor
        switch ext {
        case "pdf":
            extractor = PDFExtractor()
        case "epub":
            extractor = EPUBExtractor()
        case "txt", "text":
            extractor = TextFileExtractor()
        case "rtf":
            extractor = RTFExtractor()
        default:
            throw ExtractionError.unsupportedFormat
        }

        let result = try extractor.extractText(from: data)
        let title = result.title ?? fileName.replacingOccurrences(of: ".\(ext)", with: "")
        let author = result.author ?? "Unknown Author"

        let book = Book(
            title: title,
            author: author,
            extractedText: result.text,
            sourceFileName: fileName
        )

        modelContext.insert(book)
        try modelContext.save()

        return book
    }
}
