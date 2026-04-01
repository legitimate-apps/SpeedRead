//  TextExtractor.swift
import Foundation

struct ExtractionResult {
    let text: String
    let title: String?
    let author: String?
}

enum ExtractionError: Error {
    case invalidData
    case parsingFailed(String)
    case unsupportedFormat
}

protocol TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult
}
