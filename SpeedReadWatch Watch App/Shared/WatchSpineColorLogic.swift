import SwiftUI

/// The watch intentionally uses the classic shelf palette until a selected shelf theme is synced.
///
/// The phone's `selectedThemeId` is not available on watchOS. Changing this policy therefore
/// requires a product-level sync field, not an opportunistic color change in a watch view.
enum WatchSpineColorLogic {
    enum ThemeSource: Equatable {
        case classicOnlyUntilThemeSelectionIsSynced
    }

    static let themeSource = ThemeSource.classicOnlyUntilThemeSelectionIsSynced

    static func color(for title: String) -> Color {
        // TDD scaffold: the red test pins classic-palette resolution before either view adopts it.
        .clear
    }
}
