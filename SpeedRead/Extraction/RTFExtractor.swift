//  RTFExtractor.swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct RTFExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]

        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        } catch {
            throw ExtractionError.invalidData
        }

        let plain = attributed.string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !plain.isEmpty else {
            throw ExtractionError.parsingFailed("RTF document contains no text")
        }

        let (title, _) = TextFileExtractor.detectTitle(in: plain)
        return ExtractionResult(text: plain, title: title, author: nil)
    }
}
