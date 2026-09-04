import Foundation

struct RemoteBookDetailLogic {
    static func supportedAcquisitions(
        from acquisitions: [OPDSAcquisition]
    ) -> [OPDSAcquisition] {
        acquisitions.filter { SupportedFormat(mimeType: $0.mimeType) != nil }
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
