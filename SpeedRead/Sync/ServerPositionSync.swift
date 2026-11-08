import Foundation
import Observation
import SwiftData
import UIKit
import os

@MainActor
protocol ServerPositionPushing {
    func noteCommitted(bookId: UUID)
}

/// For a commit that must not echo back to the server — accepting the server's own position.
struct NoServerPositionPush: ServerPositionPushing {
    func noteCommitted(bookId: UUID) {}
}

/// Reading-position sync with the library server a book came from, over KOSync with anchored
/// positions. Only reading commits a position (CORPUS §4.4): commits are pushed after a quiet
/// interval and when the app leaves the foreground; a remote position is pulled when a book is
/// opened and becomes an offer, never a jump.
@Observable
@MainActor
final class ServerPositionSync: ServerPositionPushing {
    static let shared = ServerPositionSync()

    struct Offer: Equatable, Identifiable {
        var id: UUID { bookId }
        let bookId: UUID
        let serverID: UUID
        let index: Int
        let finished: Bool
        let percentage: Int
        let device: String
        let snippet: String
        let timestamp: Date

        var displayText: String {
            "Continue from \(device) — \(finished ? 100 : percentage)%"
        }
    }

    private(set) var pendingOffer: Offer?
    /// Servers not getting this device's place for a reason the reader can act on, by server id.
    private(set) var problems: [UUID: ServerSyncProblem] = [:]

    @ObservationIgnored let deviceID: String
    @ObservationIgnored let deviceName: String
    /// Held strongly: a context does not keep its container alive, and fetching through a
    /// context whose container is gone traps inside SwiftData.
    @ObservationIgnored private var container: ModelContainer?
    private var modelContext: ModelContext? { container?.mainContext }
    @ObservationIgnored private let client: KOSyncClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pushDelay: Duration
    @ObservationIgnored private var pendingPushes: Set<UUID> = []
    @ObservationIgnored private var pushTimer: Task<Void, Never>?
    @ObservationIgnored private var flushing: Task<Void, Never>?
    @ObservationIgnored private var supportCache: [String: KOSyncServerSupport] = [:]
    /// Bumped by every local commit and accepted offer; a push prepared at an older revision is
    /// not sent.
    @ObservationIgnored private var revisions: [UUID: Int] = [:]
    /// Bumped when an offer is withdrawn; a pull started under an older generation is ignored.
    @ObservationIgnored private var pullGenerations: [UUID: Int] = [:]

    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "ServerSync")
    static let deviceIDKey = "positionSyncDeviceID"
    static let declinedOffersKey = "positionSyncDeclinedOffers"

    init(
        client: KOSyncClient = KOSyncClient(),
        defaults: UserDefaults = .standard,
        deviceName: String = ServerPositionSync.defaultDeviceName,
        pushDelay: Duration = .seconds(10)
    ) {
        self.client = client
        self.defaults = defaults
        self.deviceName = deviceName
        self.pushDelay = pushDelay
        if let stored = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = stored
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: Self.deviceIDKey)
        }
    }

    static var defaultDeviceName: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: "SpeedRead (iPad)"
        case .vision: "SpeedRead (Apple Vision Pro)"
        default: "SpeedRead (iPhone)"
        }
    }

    /// The app's container; positions are read and committed through its main context, which
    /// is the context SwiftUI's views use.
    func configure(modelContainer: ModelContainer) {
        container = modelContainer
    }

    // MARK: Push

    /// Called for every committed reading position. Playback commits every few seconds, so the
    /// push waits for a quiet interval; `flush` sends it sooner when the reader leaves. Reading
    /// here also answers any offer for this book: the reader chose this place.
    func noteCommitted(bookId: UUID) {
        guard modelContext != nil else { return }
        revisions[bookId, default: 0] += 1
        dismissOffer(for: bookId)
        pendingPushes.insert(bookId)
        pushTimer?.cancel()
        let delay = pushDelay
        pushTimer = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            // The flush runs outside this timer, so a later commit's cancel cannot cancel a
            // request already on the wire.
            Task { await self?.flush() }
        }
    }

    /// Flushes run one at a time. Two in flight for the same book could reach the server out of
    /// order, and since a device may rewind its own position, the older one landing last would
    /// move the server backwards. A caller waits for any flush already running, so a background
    /// flush does not end its background time while an earlier request is still out.
    func flush() async {
        let previous = flushing
        let current = Task {
            await previous?.value
            await drainPendingPushes()
        }
        flushing = current
        await current.value
    }

    /// Flushes with background time requested, ending it exactly once: when the flush finishes or
    /// when iOS says time is up, whichever is first. An unfinished push stays queued.
    @discardableResult
    func flushInBackground(application: any BackgroundTasking = UIApplication.shared) -> Task<Void, Never> {
        let assertion = BackgroundAssertion(application: application)
        assertion.begin(name: "position-sync")
        return Task {
            await flush()
            assertion.end()
        }
    }

    private func drainPendingPushes() async {
        pushTimer?.cancel()
        pushTimer = nil
        let books = pendingPushes
        pendingPushes.removeAll()
        for bookId in books where !(await push(bookId: bookId)) {
            // Offline, a server error or an unanswered probe: keep it for the next flush rather
            // than lose the place.
            pendingPushes.insert(bookId)
        }
    }

    /// False only when the push should be retried.
    private func push(bookId: UUID) async -> Bool {
        guard let book = fetchBook(bookId), syncTarget(for: book) != nil else { return true }
        let revision = revisions[bookId, default: 0]
        let text = book.extractedText, index = book.lastReadWordIndex
        let finished = book.finishedAt != nil
        let percentage = ServerPositionLogic.pushPercentage(index: index, wordCount: book.wordCount, finished: finished)
        let anchor = finished ? nil : await Task.detached {
            ReadingAnchor.build(text: text, tokenIndex: index)?.wireSafe()
        }.value
        guard let target = syncTarget(for: book) else { return true }
        switch await support(of: target.server) {
        case nil: return false
        case .unsupported: return true
        case .credentialsRefused:
            problems[target.server.id] = .credentialsRefused
            return true
        case .anchorPositions: break
        }
        // A removed device is told so on every push; sending more would only be refused again.
        if case .deviceRemoved? = problems[target.server.id] { return true }
        // Everything above could suspend. A newer commit is queued behind this one and an accepted
        // offer must not be echoed, so a changed revision means this snapshot is not to be sent.
        guard revisions[bookId, default: 0] == revision, let target = syncTarget(for: book) else { return true }
        let position = KOSyncPush(document: target.keys[0], percentage: percentage, device: deviceName,
                                  deviceID: deviceID, anchor: anchor)
        do {
            try await client.push(position, to: OPDSRequestConfiguration(target.server))
        } catch OPDSError.deviceRemoved(let message) {
            Self.logger.error("Position push refused: this device was removed from the server's account")
            problems[target.server.id] = .deviceRemoved(message)
            return true
        } catch {
            Self.logger.error("Position push failed: \(error.localizedDescription)")
            return false
        }
        // A push that loses to another reader's further position still succeeds, so read the
        // winner back: it may be news.
        await pull(bookId: bookId)
        return true
    }

    // MARK: Pull

    /// Fetches the server's position for a book and, when it is somewhere this device has not
    /// been, offers it; when it is not, withdraws any offer it had made for the book.
    func pull(bookId: UUID) async {
        guard let book = fetchBook(bookId), let target = syncTarget(for: book),
              await support(of: target.server) == .anchorPositions else { return }
        let generation = pullGenerations[bookId, default: 0]
        var found: KOSyncRemotePosition?
        let configuration = OPDSRequestConfiguration(target.server)
        for key in target.keys {
            do {
                found = try await client.position(of: key, on: configuration)
            } catch {
                Self.logger.error("Position pull failed: \(error.localizedDescription)")
                return
            }
            if found != nil { break }
        }
        let text = book.extractedText
        let placed: (ServerPositionLogic.Placement, String)? = if let remote = found {
            await Task.detached { () -> (ServerPositionLogic.Placement, String)? in
                let prepared = AnchoredText(text)
                guard let placement = ServerPositionLogic.place(remote, in: prepared) else { return nil }
                return (placement, prepared.snippet(aroundToken: placement.index))
            }.value
        } else { nil }
        // The reader may have read, closed the book, answered the offer or turned sync off while
        // this was in flight: decide against the state as it is now, or not at all.
        guard pullGenerations[bookId, default: 0] == generation, syncTarget(for: book) != nil else { return }
        let local = ServerPositionLogic.Local(
            index: book.lastReadWordIndex, wordCount: book.wordCount,
            lastReadDate: book.lastReadDate, finished: book.finishedAt != nil
        )
        guard let remote = found, let (placement, snippet) = placed, let timestamp = remote.timestamp,
              ServerPositionLogic.shouldOffer(remote, placement: placement, local: local, deviceID: deviceID,
                                              declinedTimestamp: declinedTimestamp(for: bookId))
        else {
            if pendingOffer?.bookId == bookId { pendingOffer = nil }
            return
        }
        if let current = pendingOffer, current.bookId == bookId, current.timestamp > timestamp { return }
        let index = ReadingPositionCoordinator.clampedIndex(placement.index, wordCount: book.wordCount)
        pendingOffer = Offer(
            bookId: bookId,
            serverID: target.server.id,
            index: index,
            finished: placement.finished,
            // Where the reader will land, in this copy's own words — the figure the reader's header
            // shows after Continue. The server's figure is measured on its own copy of the book.
            percentage: book.wordCount > 0 ? Int(Double(index) / Double(book.wordCount) * 100) : 0,
            device: remote.device?.isEmpty == false ? remote.device! : "your library",
            snippet: snippet,
            timestamp: timestamp
        )
    }

    // MARK: Offer

    /// Moves the reader to the offered place as a reading commit, so the watch follows. It is not
    /// pushed back — the server already holds it — and a push queued before it is dropped, since
    /// it would send the place the reader just chose to leave.
    @discardableResult
    func accept(_ offer: Offer, sync: (any ReadingPositionSyncing)? = nil) -> Bool {
        guard pendingOffer == offer else { return false }
        pendingOffer = nil
        guard let modelContext, let book = fetchBook(offer.bookId) else { return false }
        revisions[offer.bookId, default: 0] += 1
        pendingPushes.remove(offer.bookId)
        let commit = ReadingPositionCoordinator.commit(
            offer.index, wordCount: book.wordCount, book: book, saver: modelContext,
            sync: sync, serverSync: NoServerPositionPush(), didFinish: offer.finished
        )
        return commit.didSave
    }

    func decline(_ offer: Offer) {
        guard pendingOffer == offer else { return }
        pendingOffer = nil
        var declined = defaults.dictionary(forKey: Self.declinedOffersKey) as? [String: Double] ?? [:]
        declined[offer.bookId.uuidString] = offer.timestamp.timeIntervalSince1970
        defaults.set(declined, forKey: Self.declinedOffersKey)
    }

    /// Withdraws the book's offer and any pull still in flight for it, so a late answer cannot
    /// bring the banner back.
    func dismissOffer(for bookId: UUID) {
        pullGenerations[bookId, default: 0] += 1
        if pendingOffer?.bookId == bookId { pendingOffer = nil }
    }

    /// A server's settings were saved. Its answer to the probe is asked again, since a refusal
    /// may have been a wrong password, and any problem it had is forgotten until it recurs; and
    /// when its sync is off, nothing it said stays on offer.
    func serverSettingsChanged(_ server: OPDSServer) {
        let prefix = "\(server.id.uuidString)|"
        supportCache = supportCache.filter { !$0.key.hasPrefix(prefix) }
        problems[server.id] = nil
        if !server.syncsReadingPosition, pendingOffer?.serverID == server.id { pendingOffer = nil }
    }

    func problem(for serverID: UUID) -> ServerSyncProblem? { problems[serverID] }

    private func declinedTimestamp(for bookId: UUID) -> Date? {
        let declined = defaults.dictionary(forKey: Self.declinedOffersKey) as? [String: Double]
        return declined?[bookId.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Servers

    private func fetchBook(_ bookId: UUID) -> Book? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        return try? modelContext.fetch(descriptor).first
    }

    /// The server this book syncs with and the keys it knows the book by, best first — or nil
    /// when the book did not come from a server, or that server's sync is off.
    private func syncTarget(for book: Book) -> (server: OPDSServer, keys: [String])? {
        guard let modelContext, let origin = book.origin else { return nil }
        let serverID = origin.serverID
        let descriptor = FetchDescriptor<OPDSServer>(predicate: #Predicate { $0.id == serverID })
        guard let server = try? modelContext.fetch(descriptor).first, server.syncsReadingPosition else { return nil }
        let keys = ServerPositionLogic.documentKeys(digest: book.sourceDigest, origin: origin, serverID: server.id)
        return keys.isEmpty ? nil : (server, keys)
    }

    /// Nil when the server could not be asked, so the caller retries. An answer is remembered
    /// until the launch ends or the server's settings are saved.
    private func support(of server: OPDSServer) async -> KOSyncServerSupport? {
        let key = "\(server.id.uuidString)|\(server.baseURLString)|\(server.username)"
        if let cached = supportCache[key] { return cached }
        do {
            let support = try await client.support(of: OPDSRequestConfiguration(server))
            supportCache[key] = support
            return support
        } catch {
            Self.logger.error("Sync support probe failed: \(error.localizedDescription)")
            return nil
        }
    }
}

@MainActor
protocol BackgroundTasking {
    func beginBackgroundTask(withName taskName: String?,
                             expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundTasking {}

/// One background-time assertion, ended exactly once.
@MainActor
final class BackgroundAssertion {
    private let application: any BackgroundTasking
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(application: any BackgroundTasking) {
        self.application = application
    }

    func begin(name: String) {
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
