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
        let document = try #require(PDFDocument(data: createTestPDF(pages: [
            "First page has four words",
            "Second page starts here"
        ])))
        let root = PDFOutline()
        for (index, title) in [(0, "Opening"), (1, "Second Part")] {
            let child = PDFOutline()
            child.label = title
            child.destination = PDFDestination(
                page: try #require(document.page(at: index)),
                at: .zero
            )
            root.insertChild(child, at: root.numberOfChildren)
        }
        document.outlineRoot = root
        let outlinedData = try #require(document.dataRepresentation())

        let result = try PDFExtractor().extractText(from: outlinedData)

        #expect(result.chapters == [
            ChapterMark(title: "Opening", startWordIndex: 0),
            ChapterMark(title: "Second Part", startWordIndex: 5)
        ])
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
