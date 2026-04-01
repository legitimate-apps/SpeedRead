//  SampleBookLoader.swift
import Foundation
import SwiftData

struct SampleBookLoader {
    let modelContext: ModelContext

    private static let sampleFiles = [
        "TheYellowWallpaper.epub",
        "TheMetamorphosis.epub",
        "AChristmasCarol.epub",
        "AChristmasCarol.pdf"
    ]

    /// Loads bundled sample books on first launch. No-ops if books already exist.
    func loadSampleBooksIfNeeded() {
        let descriptor = FetchDescriptor<Book>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for fileName in Self.sampleFiles {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
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
                let title = result.title ?? fileName.replacingOccurrences(of: ".\(ext)", with: "")
                let author = result.author ?? "Unknown Author"

                let book = Book(
                    title: title,
                    author: author,
                    extractedText: result.text,
                    sourceFileName: fileName
                )
                modelContext.insert(book)
            } catch {
                // Skip files that fail to parse
                continue
            }
        }

        try? modelContext.save()
    }
}
