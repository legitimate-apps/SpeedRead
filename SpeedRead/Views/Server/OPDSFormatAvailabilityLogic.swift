import Foundation

/// How a catalog entry's download formats divide into the ones SpeedRead can open and the ones it
/// cannot. `unreadableDisplayNames` is deduplicated so a catalog offering the same format twice
/// shows one badge, not two.
struct OPDSFormatAvailability: Equatable, Sendable {
    let readable: [OPDSAcquisition]
    let unreadable: [OPDSAcquisition]
    let unreadableDisplayNames: [String]
}

enum OPDSFormatAvailabilityLogic {
    static let supportRequestURL = URL(string: "https://www.legitimateapps.com/contact")!
    static let supportRequestLabel = "Send us a note"
    static let unavailableFormatMessage =
        "If you need this format, send us a note and I'll build support for it."

    static func classify(_ acquisitions: [OPDSAcquisition]) -> OPDSFormatAvailability {
        var readable: [OPDSAcquisition] = []
        var unreadable: [OPDSAcquisition] = []
        for acquisition in acquisitions {
            if isReadable(acquisition) {
                readable.append(acquisition)
            } else {
                unreadable.append(acquisition)
            }
        }
        var seenNames: Set<String> = []
        let displayNames = unreadable
            .map(\.displayFormat)
            .filter { seenNames.insert($0).inserted }
        return OPDSFormatAvailability(
            readable: readable,
            unreadable: unreadable,
            unreadableDisplayNames: displayNames
        )
    }

    static func isReadable(_ acquisition: OPDSAcquisition) -> Bool {
        SupportedFormat(mimeType: acquisition.mimeType) != nil
    }
}
