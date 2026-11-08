import Foundation

/// Why a library server is not getting this device's reading place, when the reader can do
/// something about it. Shown wherever Reading Sync is shown.
nonisolated enum ServerSyncProblem: Equatable, Sendable {
    /// The server has sync, and refused this username and password.
    case credentialsRefused
    /// The server says this device was removed from the account; its words, when it gave any.
    case deviceRemoved(String?)

    var message: String {
        switch self {
        case .credentialsRefused:
            "Your place isn't syncing: the server didn't accept this username and password. Check them, then save."
        case .deviceRemoved(let said):
            OPDSError.deviceRemoved(said).errorDescription ?? ""
        }
    }
}
