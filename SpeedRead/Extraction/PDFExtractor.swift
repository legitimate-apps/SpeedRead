//  PDFExtractor.swift
import Foundation
import PDFKit

struct PDFExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        guard let document = PDFDocument(data: data) else {
            throw ExtractionError.invalidData
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let text = page.string {
                pages.append(text)
            }
        }

        let fullText = pages.joined(separator: "\n\n")
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        return ExtractionResult(text: fullText, title: title, author: author)
    }
}
