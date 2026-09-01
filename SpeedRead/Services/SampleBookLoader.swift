//  SampleBookLoader.swift
import Foundation
import SwiftData
import os

protocol SampleBookResourceProviding {
    func data(named fileName: String) throws -> Data?
}

struct BundleSampleBookResourceProvider: SampleBookResourceProviding {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func data(named fileName: String) throws -> Data? {
        guard let url = bundle.url(forResource: fileName, withExtension: nil) else {
            return nil
        }
        return try Data(contentsOf: url)
    }
}

struct SampleBookLoader {
    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "SampleLoader")

    let modelContext: ModelContext
    let resources: any SampleBookResourceProviding

    init(
        modelContext: ModelContext,
        resources: any SampleBookResourceProviding = BundleSampleBookResourceProvider()
    ) {
        self.modelContext = modelContext
        self.resources = resources
    }

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
            do {
                guard let data = try resources.data(named: sample.fileName) else { continue }
                let ext = (sample.fileName as NSString).pathExtension.lowercased()

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
