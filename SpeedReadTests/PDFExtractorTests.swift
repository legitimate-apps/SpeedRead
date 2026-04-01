import Testing
import Foundation
import PDFKit
@testable import SpeedRead

@Suite("PDF Extractor Tests")
struct PDFExtractorTests {

    @Test func extractsTextFromPDFData() throws {
        let pdfData = createTestPDF(text: "Hello world from a PDF document")
        let extractor = PDFExtractor()
        let result = try extractor.extractText(from: pdfData)
        #expect(result.text.contains("Hello"))
        #expect(result.text.contains("world"))
        #expect(result.text.contains("PDF"))
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

    private func createTestPDF(text: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            text.draw(in: CGRect(x: 72, y: 72, width: 468, height: 648), withAttributes: attributes)
        }
    }
}
