//  DocumentImporter.swift
import Foundation
import SwiftData

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
    func importData(_ data: Data, filename: String, origin: BookOrigin? = nil) throws -> Book {
        try importBytes(data, filename: filename, origin: origin)
    }

    private func importBytes(_ data: Data, filename: String, origin: BookOrigin? = nil) throws -> Book {
        let fileExtension = (filename as NSString).pathExtension
        guard let format = SupportedFormat(fileExtension: fileExtension) else {
            throw ExtractionError.unsupportedFormat
        }

        let extractor: TextExtractor
        switch format {
        case .pdf:
            extractor = PDFExtractor()
        case .epub:
            extractor = EPUBExtractor()
        case .plainText:
            extractor = TextFileExtractor()
        case .richText:
            extractor = RTFExtractor()
        }

        let result = try extractor.extractText(from: data)
        let defaultTitle = (filename as NSString).deletingPathExtension
        let title = result.title ?? defaultTitle
        let author = result.author ?? "Unknown Author"

        let book = Book(
            title: title,
            author: author,
            extractedText: result.text,
            sourceFileName: filename,
            chapters: result.chapters
        )
        // Counted the way the reader counts, so whitespace or markers alone are no text either.
        // A scanned PDF used to land here as a 0-word book with nothing to say why.
        guard book.wordCount > 0 else {
            throw ExtractionError.noReadableText(format)
        }
        // Over the bytes exactly as received: this is what a sync server registered when it
        // served them.
        book.sourceDigest = KOReaderPartialMD5.digest(of: data)
        book.origin = origin

        modelContext.insert(book)
        try modelContext.save()

        return book
    }
}
