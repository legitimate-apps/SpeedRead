import SwiftUI
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch spine color policy")
struct WatchSpineColorTests {
    @Test func watchDeliberatelyUsesTheSharedClassicPaletteUntilThemeSelectionSyncs() {
        let title = "The Metamorphosis"

        #expect(
            WatchSpineColorLogic.themeSource
                == .classicOnlyUntilThemeSelectionIsSynced
        )
        #expect(WatchSpineColorLogic.color(for: title) == SpineColor.color(for: title))
    }

    @Test func classicResolutionIsDeterministicInTheWatchLane() {
        let first = WatchSpineColorLogic.color(for: "A Christmas Carol")
        let second = WatchSpineColorLogic.color(for: "A Christmas Carol")

        #expect(first == second)
        #expect(first == SpineColor.color(for: "A Christmas Carol"))
    }
}
