//  SampleBookLoader.swift
import Foundation
import SwiftData
import os

struct SampleBookLoader {
    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "SampleLoader")

    let modelContext: ModelContext

    private struct SampleBook {
        let fileName: String
        let title: String
        let author: String
    }

    private static let sampleBooks: [SampleBook] = [
        SampleBook(fileName: "TheYellowWallpaper.epub", title: "The Yellow Wallpaper", author: "Charlotte Perkins Gilman"),
        SampleBook(fileName: "TheMetamorphosis.epub", title: "Metamorphosis", author: "Franz Kafka"),
        SampleBook(fileName: "AChristmasCarol.epub", title: "A Christmas Carol", author: "Charles Dickens"),
        SampleBook(fileName: "AChristmasCarol.pdf", title: "A Christmas Carol", author: "Charles Dickens")
    ]

    /// Loads bundled sample books on first launch. No-ops if books already exist.
    func loadSampleBooksIfNeeded() {
        let descriptor = FetchDescriptor<Book>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for sample in Self.sampleBooks {
            guard let url = Bundle.main.url(forResource: sample.fileName, withExtension: nil) else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()

                let extractor: TextExtractor
                switch ext {
                case "pdf":
                    extractor = PDFExtractor()
                case "epub":
                    extractor = EPUBExtractor()
                default:
                    continue
                }

                let result = try extractor.extractText(from: data)
                let title = sample.title
                let author = sample.author

                let book = Book(
                    title: title,
                    author: author,
                    extractedText: result.text,
                    sourceFileName: sample.fileName,
                    chapters: result.chapters
                )
                modelContext.insert(book)
            } catch {
                // Skip files that fail to parse
                continue
            }
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save sample books: \(error.localizedDescription, privacy: .public)")
        }
    }
}
