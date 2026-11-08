import Foundation

/// Decisions for syncing a book's highlights and bookmarks with its library server. Pure: every
/// input is a value, so each rule is testable without a server or a model context.
///
/// The rules, in the server's own terms: a deletion is only ever named (a hidden row), never
/// inferred from a row being absent; a device may change only the rows it wrote itself; and a
/// local change not yet sent beats whatever the server holds.
nonisolated enum AnnotationSyncLogic {
    enum Kind: Equatable, Sendable {
        case highlight
        case bookmark
    }

    /// One local annotation as the merge needs it.
    struct Local: Equatable, Sendable {
        let id: UUID
        let annotationID: String
        let kind: Kind
        let note: String?
        /// Changed here since the server last agreed. Never true for a row this device does not own.
        let needsPush: Bool
    }

    struct NoteUpdate: Equatable, Sendable {
        let id: UUID
        let note: String?
    }

    struct Plan: Equatable, Sendable {
        /// Deleted on the server, by this app on another device or by the reader that made it.
        var deleteLocal: [UUID] = []
        /// The server's note is newer than this device's.
        var updateNote: [NoteUpdate] = []
        /// Rows from elsewhere this device does not have yet; each still has to be placed.
        var adopt: [KOSyncRemoteAnnotation] = []
    }

    /// Whether this device may change an annotation on the server: edit its note, or delete it.
    /// The server (CWNG since v4.1.48) lets an identified device change only its own rows and
    /// legacy ones that carry no device. It answers anything else with `unchanged`, and no retry
    /// can grant ownership, so another device's row is the user's to read here, not to change.
    ///
    /// - `source` nil: made here and never pulled, so this device's.
    /// - This app's source: this device's when it names no device (legacy) or names this one.
    /// - Any other reader (KOReader, Kobo, the web reader): never.
    static func isOwned(source: String?, originDevice: String?, deviceID: String) -> Bool {
        guard let source else { return true }
        guard source == KOSyncAnnotationPush.source else { return false }
        return originDevice == nil || originDevice == deviceID
    }

    /// The annotation keys a server knows a book by, best first: its own book id, then the digest
    /// of the downloaded bytes, which differs whenever the server converted or re-wrote the file.
    static func documentKey(digest: String?, origin: BookOrigin?, serverID: UUID) -> String? {
        guard let origin, origin.serverID == serverID else { return nil }
        return origin.serverBookID ?? digest
    }

    /// `forgotten` holds ids this device deleted — its own rows not yet deleted on the server,
    /// and other readers' rows, which only their reader can delete — so neither comes back.
    static func plan(local: [Local], remote: [KOSyncRemoteAnnotation], forgotten: Set<String>) -> Plan {
        var plan = Plan()
        let byID = Dictionary(local.map { ($0.annotationID.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for row in remote {
            if let mine = byID[row.annotationID.lowercased()] {
                if row.hidden {
                    plan.deleteLocal.append(mine.id)
                } else if !mine.needsPush {
                    if row.note != mine.note { plan.updateNote.append(NoteUpdate(id: mine.id, note: row.note)) }
                }
                continue
            }
            guard !row.hidden, row.quote != nil, !forgotten.contains(row.annotationID),
                  kind(of: row) != nil else { continue }
            plan.adopt.append(row)
        }
        return plan
    }

    /// What a remote row becomes here, or nil for one with no place in the text (a standalone
    /// note).
    static func kind(of row: KOSyncRemoteAnnotation) -> Kind? {
        guard row.quote != nil else { return nil }
        return row.type == .dogear ? .bookmark : .highlight
    }

    static func percentage(token: Int, wordCount: Int) -> Double {
        guard wordCount > 0 else { return 0 }
        return min(max(Double(token) / Double(wordCount), 0), 1)
    }
}
