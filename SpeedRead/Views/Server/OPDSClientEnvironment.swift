import SwiftUI

private struct OPDSClientFactoryKey: EnvironmentKey {
    static let defaultValue: () -> OPDSClient = { OPDSClient() }
}

extension EnvironmentValues {
    /// Inherited by catalog navigation, rows and detail destinations. A fresh client on the
    /// shared session remains the default for every operation.
    var opdsClientFactory: () -> OPDSClient {
        get { self[OPDSClientFactoryKey.self] }
        set { self[OPDSClientFactoryKey.self] = newValue }
    }
}
