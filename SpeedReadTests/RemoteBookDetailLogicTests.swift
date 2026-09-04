import Foundation
import Testing
@testable import SpeedRead

/// Specification for the decisions behind RemoteBookDetailView, which no test named.
@Suite("Remote book detail logic")
struct RemoteBookDetailLogicTests {

    // MARK: - The filename bug this leg exists to close

    /// MEASURED 2026-09-04 with a one-file `swift` probe, because I was about to write three
    /// wrong examples into this spec from memory:
    ///
    ///   "Book v1.2"                      -> pathExtension "2"      <- non-empty
    ///   "Vol. 2"                         -> pathExtension ""
    ///   "J. R. R. Tolkien - The Hobbit"  -> pathExtension ""
    ///   "A Tale of Two Cities. Abridged" -> pathExtension ""
    ///   "file."                          -> pathExtension ""
    ///
    /// NSString.pathExtension excludes a trailing token containing a space, so only the
    /// version-number shape triggers it. The old code asked "is there an extension?" and
    /// returned the filename untouched when there was one. The right question is "is there an
    /// extension the importer can ROUTE?" -- "2" is not, so the format must still be appended.
    @Test func aVersionNumberIsNotAnExtensionAndMustNotSuppressTheRealOne() {
        #expect(RemoteBookDetailLogic.ensureExtension(
            "Book v1.2", mimeType: "application/epub+zip", fallbackTitle: "Ignored"
        ) == "Book v1.2.epub")
    }

    @Test func aRoutableExtensionIsLeftAlone() {
        #expect(RemoteBookDetailLogic.ensureExtension(
            "Dracula.epub", mimeType: "application/epub+zip", fallbackTitle: "Ignored"
        ) == "Dracula.epub")
    }

    @Test func aRoutableExtensionInTheWrongCaseIsStillLeftAlone() {
        #expect(RemoteBookDetailLogic.ensureExtension(
            "Dracula.EPUB", mimeType: "application/epub+zip", fallbackTitle: "Ignored"
        ) == "Dracula.EPUB")
    }

    @Test func filenamesWithNoExtensionGetTheOneTheirMimeTypeImplies() {
        #expect(RemoteBookDetailLogic.ensureExtension(
            "Dracula", mimeType: "application/pdf", fallbackTitle: "Ignored"
        ) == "Dracula.pdf")
        #expect(RemoteBookDetailLogic.ensureExtension(
            "Vol. 2", mimeType: "text/plain", fallbackTitle: "Ignored"
        ) == "Vol. 2.txt")
    }

    // MARK: - Degenerate inputs a server can really send

    /// The old code produced ".epub" -- a dotfile with no basename -- when the server sent an
    /// empty filename for an untitled entry. The importer would then see extension "epub" and
    /// a title of "", so the book landed in the library nameless.
    @Test func anEmptyFilenameAndEmptyTitleStillYieldsAUsableName() {
        let name = RemoteBookDetailLogic.ensureExtension(
            "", mimeType: "application/epub+zip", fallbackTitle: ""
        )
        #expect(name.hasSuffix(".epub"))
        #expect(name.hasPrefix(".") == false, "a leading dot makes it a hidden file with no name")
        #expect(name.count > ".epub".count)
    }

    @Test func anEmptyFilenameFallsBackToTheEntryTitle() {
        #expect(RemoteBookDetailLogic.ensureExtension(
            "", mimeType: "application/pdf", fallbackTitle: "A Christmas Carol"
        ) == "A Christmas Carol.pdf")
    }

    /// A title is server-supplied text, not a filename. A path separator in it must not be able
    /// to redirect where the file is written.
    @Test func pathSeparatorsInATitleCannotEscapeIntoTheFilename() {
        let name = RemoteBookDetailLogic.ensureExtension(
            "", mimeType: "application/pdf", fallbackTitle: "../../etc/passwd"
        )
        #expect(name.contains("/") == false)
        #expect(name.hasSuffix(".pdf"))
    }

    // MARK: - Which acquisitions are offered at all

    @Test func onlyFormatsTheImporterCanReadAreOffered() {
        let entry = [
            acquisition("https://x/a.epub", "application/epub+zip"),
            acquisition("https://x/b.mobi", "application/x-mobipocket-ebook"),
            acquisition("https://x/c.pdf", "application/pdf"),
            acquisition("https://x/d.html", "text/html"),
        ]
        let offered = RemoteBookDetailLogic.supportedAcquisitions(from: entry)
        #expect(offered.map(\.mimeType) == ["application/epub+zip", "application/pdf"])
    }

    @Test func anEntryWithNoReadableFormatOffersNothing() {
        let entry = [acquisition("https://x/a.mobi", "application/x-mobipocket-ebook")]
        #expect(RemoteBookDetailLogic.supportedAcquisitions(from: entry).isEmpty)
    }

    // MARK: - Selection must never index out of bounds in either direction

    @Test func aSelectionWithinRangeReturnsThatAcquisition() {
        let offered = [acquisition("https://x/a.epub", "application/epub+zip"),
                       acquisition("https://x/b.pdf", "application/pdf")]
        #expect(RemoteBookDetailLogic.resolvedAcquisition(at: 1, in: offered)?.mimeType == "application/pdf")
    }

    /// The old guard checked only the upper bound, so a negative index would have subscripted
    /// out of bounds and crashed. Not reachable from the Picker today; unrepresentable now.
    @Test func anOutOfRangeSelectionFallsBackToTheFirstRatherThanCrashing() {
        let offered = [acquisition("https://x/a.epub", "application/epub+zip"),
                       acquisition("https://x/b.pdf", "application/pdf")]
        #expect(RemoteBookDetailLogic.resolvedAcquisition(at: 99, in: offered)?.mimeType == "application/epub+zip")
        #expect(RemoteBookDetailLogic.resolvedAcquisition(at: -1, in: offered)?.mimeType == "application/epub+zip")
    }

    @Test func selectingFromAnEmptyListYieldsNothingRatherThanCrashing() {
        #expect(RemoteBookDetailLogic.resolvedAcquisition(at: 0, in: []) == nil)
        #expect(RemoteBookDetailLogic.resolvedAcquisition(at: -1, in: []) == nil)
    }

    // MARK: - Helper

    private func acquisition(_ url: String, _ mime: String) -> OPDSAcquisition {
        OPDSAcquisition(url: URL(string: url)!, mimeType: mime, length: nil, title: nil)
    }
}
