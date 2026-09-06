import Foundation

/// Each test instance owns a separate domain; never writes the host application's defaults.
final class IsolatedDefaults {
    let name = "SpeedReadTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}
