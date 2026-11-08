import Foundation
import Testing
@testable import SpeedRead

@Suite("Annotation sync logic")
struct AnnotationSyncLogicTests {
    private static let mineID = UUID()

    private static func local(_ annotationID: String, id: UUID = UUID(), note: String? = nil,
                              needsPush: Bool = false) -> AnnotationSyncLogic.Local {
        .init(id: id, annotationID: annotationID, kind: .highlight, note: note, needsPush: needsPush)
    }

    private static func remote(_ id: String, source: String = "koreader", type: KOSyncAnnotationType? = .highlight,
                               quote: TextQuote? = TextQuote(exact: "w1", prefix: "", suffix: ""),
                               note: String? = nil, hidden: Bool = false) -> KOSyncRemoteAnnotation {
        KOSyncRemoteAnnotation(annotationID: id, source: source, type: type, quote: quote, note: note, hidden: hidden,
                               deviceOriginID: nil, percentage: nil)
    }

    /// The server's rule since CWNG v4.1.48: a device changes only its own rows and legacy ones.
    @Test(arguments: [
        (nil, nil, true),                            // made here, never pulled
        ("textquote", nil, true),                    // legacy: the server names no device
        ("textquote", "this-device", true),          // written by this device before
        ("textquote", "other-device", false),        // this app on another device
        ("koreader", nil, false),                    // another reader, whatever the device
        ("koreader", "this-device", false),
    ] as [(String?, String?, Bool)])
    func onlyThisDevicesOwnAndLegacyRowsAreOwned(source: String?, origin: String?, owned: Bool) {
        #expect(AnnotationSyncLogic.isOwned(source: source, originDevice: origin, deviceID: "this-device") == owned)
    }

    @Test func aDeletionMadeElsewhereDeletesTheLocalCopy() {
        let id = UUID()
        let plan = AnnotationSyncLogic.plan(local: [Self.local("kr-1", id: id)],
                                            remote: [Self.remote("kr-1", hidden: true)], forgotten: [])
        #expect(plan.deleteLocal == [id])
        #expect(plan.adopt.isEmpty)
    }

    @Test func absenceIsNeverADeletion() {
        let plan = AnnotationSyncLogic.plan(local: [Self.local("kr-1")], remote: [], forgotten: [])
        #expect(plan == AnnotationSyncLogic.Plan())
    }

    @Test func aRemoteNoteReplacesALocalOneWithNoUnsentChange() {
        let id = UUID()
        let plan = AnnotationSyncLogic.plan(local: [Self.local("kr-1", id: id, note: "old")],
                                            remote: [Self.remote("kr-1", note: "new")], forgotten: [])
        #expect(plan.updateNote == [.init(id: id, note: "new")])
    }

    @Test func anUnsentLocalChangeBeatsTheServer() {
        let plan = AnnotationSyncLogic.plan(local: [Self.local("A", note: "mine", needsPush: true)],
                                            remote: [Self.remote("a", source: "textquote", note: "theirs")], forgotten: [])
        #expect(plan.updateNote.isEmpty)
        #expect(plan.deleteLocal.isEmpty)
    }

    @Test func otherReadersAnnotationsAreAdoptedOnceAndOnlyWithAPlace() {
        let plan = AnnotationSyncLogic.plan(
            local: [Self.local("have")],
            remote: [Self.remote("have"), Self.remote("new"), Self.remote("bookmark", type: .dogear),
                     Self.remote("standalone", type: .note, quote: nil), Self.remote("gone", hidden: true),
                     Self.remote("deleted-here")],
            forgotten: ["deleted-here"]
        )
        #expect(plan.adopt.map(\.annotationID) == ["new", "bookmark"])
        #expect(plan.adopt.map(AnnotationSyncLogic.kind(of:)) == [.highlight, .bookmark])
    }

    @Test func theServersBookIDIsPreferredToTheDigest() {
        let server = UUID()
        let origin = BookOrigin(serverID: server, entryID: "urn:uuid:1", serverBookID: "42")
        #expect(AnnotationSyncLogic.documentKey(digest: "d1g", origin: origin, serverID: server) == "42")
        let noID = BookOrigin(serverID: server, entryID: "urn:uuid:1", serverBookID: nil)
        #expect(AnnotationSyncLogic.documentKey(digest: "d1g", origin: noID, serverID: server) == "d1g")
        #expect(AnnotationSyncLogic.documentKey(digest: "d1g", origin: origin, serverID: UUID()) == nil)
        #expect(AnnotationSyncLogic.documentKey(digest: "d1g", origin: nil, serverID: server) == nil)
    }
}
