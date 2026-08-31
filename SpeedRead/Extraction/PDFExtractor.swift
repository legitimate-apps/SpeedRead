//  PDFExtractor.swift
import Foundation
import PDFKit

struct PDFExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        guard let document = PDFDocument(data: data) else {
            throw ExtractionError.invalidData
        }

        var pages: [String] = []
        var pageStartWordIndices: [Int: Int] = [:]
        var startWordIndex = 0
        for i in 0..<document.pageCount {
            pageStartWordIndices[i] = startWordIndex
            if let page = document.page(at: i),
               let text = page.string {
                pages.append(text)
                startWordIndex += Book.tokenize(text).count
            }
        }

        let fullText = pages.joined(separator: "\n\n")
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        return ExtractionResult(
            text: fullText,
            title: title,
            author: author,
            chapters: Self.chapterMarks(
                in: document,
                pageStartWordIndices: pageStartWordIndices,
                wordCount: startWordIndex
            )
        )
    }

    private static func chapterMarks(
        in document: PDFDocument,
        pageStartWordIndices: [Int: Int],
        wordCount: Int
    ) -> [ChapterMark] {
        guard wordCount > 0, let root = document.outlineRoot else { return [] }
        var positioned: [(order: Int, mark: ChapterMark)] = []
        var order = 0

        func visit(_ outline: PDFOutline) {
            if let label = outline.label?
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " "),
               !label.isEmpty,
               let page = outline.destination?.page {
                let pageIndex = document.index(for: page)
                if let start = pageStartWordIndices[pageIndex], start < wordCount {
                    positioned.append((order, ChapterMark(
                        title: label,
                        startWordIndex: start
                    )))
                    order += 1
                }
            }
            for childIndex in 0..<outline.numberOfChildren {
                if let child = outline.child(at: childIndex) {
                    visit(child)
                }
            }
        }

        for childIndex in 0..<root.numberOfChildren {
            if let child = root.child(at: childIndex) {
                visit(child)
            }
        }

        var seen: Set<ChapterMark> = []
        return positioned
            .sorted {
                if $0.mark.startWordIndex == $1.mark.startWordIndex {
                    return $0.order < $1.order
                }
                return $0.mark.startWordIndex < $1.mark.startWordIndex
            }
            .compactMap { seen.insert($0.mark).inserted ? $0.mark : nil }
    }
}
