import Foundation

/// Composition decisions left at the `WatchRSVPView` boundary after session behaviour is extracted.
enum WatchRSVPViewLogic {
    static func recordBrowsePosition(
        book: WatchBook?,
        index: Int,
        engineState: RSVPEngine.State,
        in library: inout WatchLibrary
    ) -> Bool {
        // TDD scaffold: the red test pins that browsing is device-local and playback is not browsing.
        false
    }
}
