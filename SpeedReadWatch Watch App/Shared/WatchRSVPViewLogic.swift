import Foundation

/// Composition decisions left at the `WatchRSVPView` boundary after session behaviour is extracted.
enum WatchRSVPViewLogic {
    static func recordBrowsePosition(
        book: WatchBook?,
        index: Int,
        engineState: RSVPEngine.State,
        in library: inout WatchLibrary
    ) -> Bool {
        guard engineState != .playing, let book else { return false }
        return library.updateBrowsePosition(bookId: book.id, index: index)
    }
}
