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
        return try importBytes(data, filename: fileName)
    }

    /// Import already-in-memory bytes (e.g. from an OPDS download). No
    /// security-scoped resource handling; caller has already obtained the bytes.
    func importData(_ data: Data, filename: String) throws -> Book {
        try importBytes(data, filename: filename)
    }

    private func importBytes(_ data: Data, filename: String) throws -> Book {
        let ext = (filename as NSString).pathExtension.lowercased()

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
        let defaultTitle = ext.isEmpty
            ? filename
            : filename.replacingOccurrences(of: ".\(ext)", with: "")
        let title = result.title ?? defaultTitle
        let author = result.author ?? "Unknown Author"

        let book = Book(
            title: title,
            author: author,
            extractedText: result.text,
            sourceFileName: filename
        )

        modelContext.insert(book)
        try modelContext.save()

        return book
    }
}
