import Foundation
import Testing
@testable import SpeedRead

struct OPDSAcquisitionLabelLogicTests {
    // Mutations: MIME-only labels make distinct EPUB downloads indistinguishable;
    // deduplicating by MIME would silently remove a real download from this capture.
    @Test func capturedEPUBVariantsHaveDistinctLabels() throws {
        let feed = try OPDSAtomParser(baseURL: URL(fileURLWithPath: "/")).parse(
            data: OPDSCapturedFixture.data("cwng-acquisition-hot"))
        let book = try #require(feed.entries.first)
        #expect(book.acquisitions.count == 2)
        #expect(Set(book.acquisitions.map(\.url)).count == 2)
        let labels = OPDSAcquisitionLabelLogic.labels(for: book.acquisitions)
        #expect(labels.count == 2)
        #expect(Set(labels).count == 2)
        #expect(labels.allSatisfy { $0.hasPrefix("EPUB") && $0.contains("KB") })
    }

    // Mutations: omitting title/size/ordinal fallbacks produces duplicate or empty choices.
    @Test func uniqueFormatsAndAmbiguousSizes() {
        #expect(OPDSAcquisitionLabelLogic.labels(for: []).isEmpty)
        #expect(OPDSAcquisitionLabelLogic.labels(for: [acq(), acq("application/pdf")]) == ["EPUB", "PDF"])
        #expect(OPDSAcquisitionLabelLogic.labels(for: [acq(title: "Illustrated"), acq(title: "Plain")]) == ["EPUB · Illustrated", "EPUB · Plain"])
        #expect(OPDSAcquisitionLabelLogic.labels(for: [acq(title: " "), acq()]) == ["EPUB (1)", "EPUB (2)"])
        let sameSize = OPDSAcquisitionLabelLogic.labels(for: [acq(size: 1000), acq(size: 1000)])
        #expect(Set(sameSize).count == 2)
        #expect(sameSize[0].hasSuffix("(1)") && sameSize[1].hasSuffix("(2)"))
    }
    private func acq(_ mime: String = "application/epub+zip", title: String? = nil, size: Int? = nil) -> OPDSAcquisition {
        .init(url: URL(fileURLWithPath: "/book"), mimeType: mime, length: size, title: title)
    }

}
