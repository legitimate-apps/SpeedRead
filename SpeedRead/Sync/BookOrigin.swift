import Foundation

/// Where a downloaded book came from: the keys a sync server can match it on besides the
/// digest of its bytes. Captured at download because nothing afterwards can recover them.
nonisolated struct BookOrigin: Hashable, Sendable {
    let serverID: UUID
    /// The OPDS entry `<id>` (Calibre-Web serves `urn:uuid:<calibre book uuid>`).
    let entryID: String
    /// The server's own book id, when its acquisition URL carries one.
    let serverBookID: String?

    /// Calibre-Web and its forks serve acquisitions at `…/opds/download/<book id>/<format>/`.
    /// Any other shape yields nil rather than a guess.
    static func serverBookID(fromAcquisition url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.lastIndex(of: "download"), i > 0, parts[i - 1] == "opds",
              parts.indices.contains(i + 1) else { return nil }
        let id = parts[i + 1]
        return !id.isEmpty && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber) ? id : nil
    }
}
