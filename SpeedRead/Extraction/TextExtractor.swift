//  TextExtractor.swift
import Foundation

struct ExtractionResult {
    let text: String
    let title: String?
    let author: String?
    let chapters: [ChapterMark]

    init(
        text: String,
        title: String?,
        author: String?,
        chapters: [ChapterMark] = []
    ) {
        self.text = text
        self.title = title
        self.author = author
        self.chapters = chapters
    }
}

enum ExtractionError: Error, Equatable {
    case invalidData
    case parsingFailed(String)
    case unsupportedFormat
}

protocol TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult
}
