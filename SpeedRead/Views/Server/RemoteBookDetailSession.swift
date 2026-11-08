import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class RemoteBookDetailSession {
    var selectedAcquisitionIndex: Int = 0
    private(set) var downloading = false
    private(set) var downloadError: String?
    private(set) var coverImage: Image?

    func loadCover(entry: OPDSEntry, on server: OPDSServer, makeClient: () -> OPDSClient) async {
        guard let url = entry.coverURL ?? entry.thumbnailURL else { return }
        if let cached = OPDSCoverCache.shared.image(for: url) {
            coverImage = cached
            return
        }
        let client = makeClient()
        do {
            let payload = try await client.download(from: url, on: OPDSRequestConfiguration(server))
            #if canImport(UIKit)
            if let ui = UIImage(data: payload.data) {
                let image = Image(uiImage: ui)
                OPDSCoverCache.shared.store(image, for: url)
                coverImage = image
            }
            #endif
        } catch {
            // Cover failures are non-fatal — caller stays on the placeholder.
        }
    }

    func performDownload(entry: OPDSEntry, on server: OPDSServer, modelContext: ModelContext, makeClient: () -> OPDSClient, onAdded: (String) -> Void, dismiss: () -> Void) async {
        let supportedAcquisitions = RemoteBookDetailLogic.supportedAcquisitions(
            from: entry.acquisitions
        )
        guard let acquisition = RemoteBookDetailLogic.resolvedAcquisition(
            at: selectedAcquisitionIndex,
            in: supportedAcquisitions
        ) else { return }
        downloading = true
        downloadError = nil
        let client = makeClient()
        do {
            let file = try await client.downloadFile(from: acquisition.url, on: OPDSRequestConfiguration(server))
            defer { file.remove() }
            let filename = RemoteBookDetailLogic.ensureExtension(
                file.filename,
                mimeType: acquisition.mimeType,
                fallbackTitle: entry.title
            )
            let importer = DocumentImporter(modelContext: modelContext)
            let origin = BookOrigin(
                serverID: server.id,
                entryID: entry.id,
                serverBookID: BookOrigin.serverBookID(fromAcquisition: acquisition.url)
            )
            let book = try importer.importDownloaded(at: file.location, filename: filename, origin: origin)
            onAdded(book.title)
            dismiss()
        } catch {
            let failure = RemoteBookDetailLogic.downloadFailure(
                error, among: supportedAcquisitions
            )
            downloadError = failure.message
            if let alternative = failure.alternativeIndex {
                selectedAcquisitionIndex = alternative
            }
        }
        downloading = false
    }
}
