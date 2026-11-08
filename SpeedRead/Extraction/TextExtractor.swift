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

/// Every case reads as a sentence a reader can act on, because both import paths show
/// `localizedDescription` as it is. Before this conformance existed, the library's alert said
/// "The operation couldn't be completed. (SpeedRead.ExtractionError error 1.)" and a server
/// download showed the enum's own spelling.
nonisolated enum ExtractionError: LocalizedError, Equatable {
    case invalidData
    /// The detail is for tests and logs; it never reaches the reader.
    case parsingFailed(String)
    case unsupportedFormat
    /// The file opened, but it holds no words: a scanned or image-only PDF, a picture-book EPUB.
    case noReadableText(SupportedFormat)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "SpeedRead couldn't open this file. It may be damaged, or not the kind of file its name says."
        case .parsingFailed:
            "This book is damaged, so SpeedRead couldn't read its text."
        case .unsupportedFormat:
            "SpeedRead reads EPUB, PDF, plain text and RTF files."
        case .noReadableText(.pdf):
            "This PDF has no text in it, only pictures of its pages. It's probably a scan, and SpeedRead needs a book's text to read it."
        case .noReadableText:
            "This file has no text in it for SpeedRead to read."
        }
    }
}

protocol TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult
}
