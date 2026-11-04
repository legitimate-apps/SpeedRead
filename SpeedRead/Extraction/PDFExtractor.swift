//  PDFExtractor.swift
import Foundation
import PDFKit

struct PDFExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        guard let document = PDFDocument(data: data) else {
            throw ExtractionError.invalidData
        }

        let pages = Self.assemble(pageTexts: (0..<document.pageCount).map { document.page(at: $0)?.string })
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        return ExtractionResult(
            text: pages.text,
            title: title,
            author: author,
            chapters: Self.chapterMarks(
                in: document,
                pageStartWordIndices: pages.startWordIndices,
                wordCount: pages.wordCount
            )
        )
    }

    /// Joins the pages and records the word each one starts at. Markers come out first, so they
    /// never count as words and a chapter's offset matches the text the reader gets.
    static func assemble(pageTexts: [String?]) -> (text: String, startWordIndices: [Int: Int], wordCount: Int) {
        var pages: [String] = []
        var startWordIndices: [Int: Int] = [:]
        var wordCount = 0
        for (index, pageText) in pageTexts.enumerated() {
            startWordIndices[index] = wordCount
            guard let pageText else { continue }
            let text = AttachmentMarkers.removed(from: pageText)
            pages.append(text)
            wordCount += Book.tokenize(text).count
        }
        return (pages.joined(separator: "\n\n"), startWordIndices, wordCount)
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
