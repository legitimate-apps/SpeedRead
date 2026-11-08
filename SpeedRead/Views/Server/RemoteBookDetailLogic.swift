import Foundation

struct RemoteBookDetailLogic {
    struct DownloadFailure: Equatable {
        let message: String
        /// A different format of the same book worth trying, as an index into the supported list.
        let alternativeIndex: Int?
    }

    /// What the detail page says when a download does not become a book. When the chosen file
    /// had no text and the server offers the book in another format the importer reads, that
    /// format is named and handed back so the page can select it: one tap tries it.
    static func downloadFailure(
        _ error: Error,
        among supported: [OPDSAcquisition]
    ) -> DownloadFailure {
        let base: String
        switch error {
        case let opds as OPDSError:
            base = opds.errorDescription ?? error.localizedDescription
        case let extraction as ExtractionError:
            base = extraction.errorDescription ?? error.localizedDescription
        default:
            base = error.localizedDescription
        }
        guard case ExtractionError.noReadableText(let failed)? = error as? ExtractionError,
              let index = alternativeIndex(to: failed, among: supported) else {
            return DownloadFailure(message: base, alternativeIndex: nil)
        }
        let name = supported[index].displayFormat
        return DownloadFailure(
            message: "\(base) Your server also has this book as \(name), which is selected now. Tap Download to try it.",
            alternativeIndex: index
        )
    }

    private static func alternativeIndex(
        to failed: SupportedFormat,
        among supported: [OPDSAcquisition]
    ) -> Int? {
        let others = supported.indices.filter {
            guard let format = SupportedFormat(mimeType: supported[$0].mimeType) else { return false }
            return format != failed
        }
        // EPUB first: it is the format most likely to carry a real text layer.
        return others.first { supported[$0].mimeType == "application/epub+zip" } ?? others.first
    }

    static func supportedAcquisitions(
        from acquisitions: [OPDSAcquisition]
    ) -> [OPDSAcquisition] {
        OPDSFormatAvailabilityLogic.classify(acquisitions).readable
    }

    static func resolvedAcquisition(
        at index: Int,
        in acquisitions: [OPDSAcquisition]
    ) -> OPDSAcquisition? {
        guard acquisitions.indices.contains(index) else {
            return acquisitions.first
        }
        return acquisitions[index]
    }

    static func ensureExtension(
        _ filename: String,
        mimeType: String,
        fallbackTitle: String
    ) -> String {
        let existingExtension = (filename as NSString).pathExtension
        if SupportedFormat(fileExtension: existingExtension) != nil {
            return filename
        }

        let sanitizedTitle = fallbackTitle
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = filename.isEmpty ? sanitizedTitle : filename
        let usableBase = base.isEmpty ? "Untitled" : base

        guard let format = SupportedFormat(mimeType: mimeType) else {
            return usableBase
        }
        return "\(usableBase).\(format.fileExtension)"
    }
}
