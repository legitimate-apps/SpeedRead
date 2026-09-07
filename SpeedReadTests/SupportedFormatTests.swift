import Foundation
import Testing
@testable import SpeedRead

/// Specification for the single source of truth about which formats SpeedRead can read.
///
/// Before this type, three places decided that independently: DocumentImporter routed on a
/// switch over file extensions, the OPDS detail view filtered acquisitions on a mime-type
/// whitelist, and the library's file importer listed UTTypes. Nothing kept them in agreement,
/// and the mime list already carried entries the extension switch could not route.
@Suite("Supported formats")
@MainActor
struct SupportedFormatTests {

    @Test func everyFormatRoundTripsThroughItsFileExtension() {
        for format in SupportedFormat.allCases {
            #expect(SupportedFormat(fileExtension: format.fileExtension) == format)
        }
    }

    @Test func everyFormatIsReachableFromEveryMimeTypeItClaims() {
        for format in SupportedFormat.allCases {
            for mime in format.mimeTypes {
                #expect(SupportedFormat(mimeType: mime) == format,
                        "mime \(mime) should resolve to \(format)")
            }
        }
    }

    /// The OPDS filter and the importer must not be able to disagree: if a server offers a
    /// format the detail view accepts, the importer has to be able to route it. That was the
    /// actual defect shape -- two independent lists, one of them broader.
    @Test func noMimeTypeIsAcceptedThatTheImporterCannotRoute() {
        for format in SupportedFormat.allCases {
            for mime in format.mimeTypes {
                let routed = SupportedFormat(mimeType: mime)
                #expect(routed != nil)
                #expect(SupportedFormat(fileExtension: routed!.fileExtension) != nil)
            }
        }
    }

    @Test func extensionMatchingIgnoresCase() {
        #expect(SupportedFormat(fileExtension: "EPUB") == .epub)
        #expect(SupportedFormat(fileExtension: "Pdf") == .pdf)
    }

    @Test func unknownExtensionsAndMimeTypesResolveToNothing() {
        #expect(SupportedFormat(fileExtension: "mobi") == nil)
        #expect(SupportedFormat(fileExtension: "2") == nil)     // the "Book v1.2" case
        #expect(SupportedFormat(fileExtension: "") == nil)
        #expect(SupportedFormat(mimeType: "application/x-mobipocket-ebook") == nil)
        #expect(SupportedFormat(mimeType: "") == nil)
    }

    /// `.txt` and `.text` both route to plain text, so the extension set is larger than the
    /// case set. Pinned because a naive `allCases.map(\.fileExtension)` lookup would drop one.
    @Test func plainTextIsReachableFromBothOfItsExtensions() {
        #expect(SupportedFormat(fileExtension: "txt") == .plainText)
        #expect(SupportedFormat(fileExtension: "text") == .plainText)
    }

    @Test func richTextIsReachableFromBothOfItsMimeTypes() {
        #expect(SupportedFormat(mimeType: "application/rtf") == .richText)
        #expect(SupportedFormat(mimeType: "text/rtf") == .richText)
    }
}
