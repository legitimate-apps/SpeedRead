import Foundation
import Testing
@testable import SpeedRead

@Suite("OPDS format availability logic")
struct OPDSFormatAvailabilityLogicTests {
    @Test("A mixed list separates readable and unreadable acquisitions")
    func mixedListSeparatesReadableAndUnreadableAcquisitions() {
        let availability = OPDSFormatAvailabilityLogic.classify([
            acquisition("book.epub", mimeType: "application/epub+zip"),
            acquisition("book.mobi", mimeType: "application/x-mobipocket-ebook"),
            acquisition("book.pdf", mimeType: "application/pdf"),
            acquisition("book.html", mimeType: "text/html"),
        ])

        #expect(availability.readable.map(\.mimeType) == [
            "application/epub+zip",
            "application/pdf",
        ])
        #expect(availability.unreadable.map(\.mimeType) == [
            "application/x-mobipocket-ebook",
            "text/html",
        ])
        #expect(availability.unreadableDisplayNames == ["MOBI", "HTML"])
    }

    @Test("An all-unreadable list preserves every unavailable acquisition")
    func allUnreadableListPreservesEveryUnavailableAcquisition() {
        let availability = OPDSFormatAvailabilityLogic.classify([
            acquisition("book.azw", mimeType: "application/vnd.amazon.ebook"),
            acquisition("book.html", mimeType: "text/html"),
        ])

        #expect(availability.readable.isEmpty)
        #expect(availability.unreadable.count == 2)
        #expect(availability.unreadableDisplayNames == ["AZW", "HTML"])
    }

    @Test("An empty list produces empty availability groups")
    func emptyListProducesEmptyAvailabilityGroups() {
        let availability = OPDSFormatAvailabilityLogic.classify([])

        #expect(availability.readable.isEmpty)
        #expect(availability.unreadable.isEmpty)
        #expect(availability.unreadableDisplayNames.isEmpty)
    }

    @Test("Duplicate MOBI acquisitions collapse to one unavailable badge name")
    func duplicateMOBIAcquisitionsCollapseToOneUnavailableBadgeName() {
        let availability = OPDSFormatAvailabilityLogic.classify([
            acquisition("first.mobi", mimeType: "application/x-mobipocket-ebook"),
            acquisition("second.mobi", mimeType: "application/x-mobipocket-ebook"),
        ])

        #expect(availability.unreadable.count == 2)
        #expect(availability.unreadableDisplayNames == ["MOBI"])
    }

    @Test("The support link points to the contact page")
    func supportLinkPointsToTheContactPage() {
        #expect(
            OPDSFormatAvailabilityLogic.supportRequestURL.absoluteString
                == "https://www.legitimateapps.com/contact"
        )
    }

    private func acquisition(_ path: String, mimeType: String) -> OPDSAcquisition {
        OPDSAcquisition(
            url: URL(string: "https://catalog.example/\(path)")!,
            mimeType: mimeType,
            length: nil,
            title: nil
        )
    }
}
