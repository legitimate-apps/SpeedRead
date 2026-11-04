import Testing
import Foundation
import PDFKit
@testable import SpeedRead

@Suite("PDF Extractor Tests")
@MainActor
struct PDFExtractorTests {

    @Test func extractsTextFromPDFData() throws {
        let pdfData = createTestPDF(text: "Hello world from a PDF document")
        let extractor = PDFExtractor()
        let result = try extractor.extractText(from: pdfData)
        #expect(result.text.contains("Hello"))
        #expect(result.text.contains("world"))
        #expect(result.text.contains("PDF"))
        #expect(result.chapters.isEmpty)
    }

    @Test func emptyPDFReturnsEmptyText() throws {
        let pdfData = createTestPDF(text: "")
        let extractor = PDFExtractor()
        let result = try extractor.extractText(from: pdfData)
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func invalidDataThrows() {
        let extractor = PDFExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not a pdf".utf8))
        }
    }

    @Test func outlineProducesChapterTitlesAtPageTokenOffsets() throws {
        let result = try PDFExtractor().extractText(from: Self.outlinedPDF(
            pages: ["one two three four five", "six seven eight"],
            chapters: ["Opening", "Second Part"]
        ))

        #expect(result.text == "one two three four five\n\nsix seven eight")
        #expect(result.chapters == [
            ChapterMark(title: "Opening", startWordIndex: 0),
            ChapterMark(title: "Second Part", startWordIndex: 5)
        ])
    }

    @Test func pageOffsetsCountTheWordsLeftAfterMarkersComeOut() {
        let pages = PDFExtractor.assemble(pageTexts: ["\u{FFFC}\nOne two", nil, "three\n\u{FFFC}", "four"])

        #expect(pages.text == "One two\n\nthree\n\nfour")
        #expect(pages.startWordIndices == [0: 0, 1: 2, 2: 2, 3: 3])
        #expect(pages.wordCount == 4)
    }

    /// A PDF with one chapter per page, written out by hand. PDFKit can't build this fixture any
    /// more: as of OS 27 `dataRepresentation()` and `write(to:)` both drop the document's outline
    /// (OBSERVED on macOS 27.2). What this guards is reading a book's outline, and that still works.
    private static func outlinedPDF(pages: [String], chapters: [String]) -> Data {
        let font = "<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>"
        let firstPage = 3
        let firstContent = firstPage + pages.count
        let outlineRoot = firstContent + pages.count
        func object(_ n: Int) -> String { "\(n) 0 R" }
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines \(object(outlineRoot)) >>",
            "<< /Type /Pages /Count \(pages.count) /Kids [\(pages.indices.map { object(firstPage + $0) }.joined(separator: " "))] >>"
        ]
        objects += pages.indices.map {
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources \(font) /Contents \(object(firstContent + $0)) >>"
        }
        objects += pages.map {
            let content = "BT /F1 12 Tf 72 700 Td (\($0)) Tj ET"
            return "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
        }
        objects.append("<< /Type /Outlines /Count \(chapters.count) /First \(object(outlineRoot + 1)) /Last \(object(outlineRoot + chapters.count)) >>")
        objects += chapters.indices.map { index in
            let previous = index > 0 ? " /Prev \(object(outlineRoot + index))" : ""
            let next = index < chapters.count - 1 ? " /Next \(object(outlineRoot + index + 2))" : ""
            return "<< /Title (\(chapters[index])) /Parent \(object(outlineRoot))\(previous)\(next) /Dest [\(object(firstPage + index)) /XYZ 0 792 0] >>"
        }

        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let table = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    private func createTestPDF(text: String) -> Data {
        createTestPDF(pages: [text])
    }

    private func createTestPDF(pages: [String]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for text in pages {
                context.beginPage()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12)
                ]
                text.draw(
                    in: CGRect(x: 72, y: 72, width: 468, height: 648),
                    withAttributes: attributes
                )
            }
        }
    }
}
