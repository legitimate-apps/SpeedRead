import Foundation
import SwiftData
import UIKit
import os

@MainActor
protocol AnnotationChangeNoting {
    func noteChanged(bookId: UUID)
}

/// Highlight, note and bookmark sync with the library server a book came from. Each annotation
/// travels as its words (a text quote), so it lands on the same passage in every reader the
/// server serves. A book is synced when it is opened and, after a local change, once things are
/// quiet or the app leaves the foreground: pull first, so a deletion made elsewhere is applied
/// before anything is sent, then push what changed here.
@MainActor
final class ServerAnnotationSync: AnnotationChangeNoting {
    static let shared = ServerAnnotationSync()

    /// The KOSync device id this device already uses for positions, so the server sees one device.
    let deviceID: String
    let deviceName: String
    /// Held strongly: a context does not keep its container alive.
    private var container: ModelContainer?
    private var modelContext: ModelContext? { container?.mainContext }
    private let client: KOSyncClient
    private let defaults: UserDefaults
    private let pushDelay: Duration
    private var pendingBooks: Set<UUID> = []
    private var pushTimer: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var supportCache: [String: Bool] = [:]

    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "AnnotationSync")
    /// Book id → ids of this app's rows deleted here and not yet deleted on the server.
    static let pendingDeletesKey = "annotationSyncPendingDeletes"
    /// Book id → ids of other readers' rows deleted here. Only their reader can delete them on
    /// the server, so this device remembers not to take them back.
    static let forgottenKey = "annotationSyncForgotten"

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
        if let stored = defaults.string(forKey: ServerPositionSync.deviceIDKey) {
            deviceID = stored
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: ServerPositionSync.deviceIDKey)
        }
    }

    func configure(modelContainer: ModelContainer) {
        container = modelContainer
    }

    // MARK: Local changes

    /// A highlight or bookmark was added or its note changed. Sent after a quiet interval, so a
    /// burst of highlighting becomes one request.
    func noteChanged(bookId: UUID) {
        guard modelContext != nil else { return }
        pendingBooks.insert(bookId)
        pushTimer?.cancel()
        let delay = pushDelay
        pushTimer = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            Task { await self?.flush() }
        }
    }

    func delete(_ highlight: Highlight, in context: ModelContext) {
        let bookId = highlight.book?.id
        remember(highlight.annotationID, editable: highlight.isEditableOnServer, bookId: bookId)
        context.delete(highlight)
        try? context.save()
        if let bookId { noteChanged(bookId: bookId) }
    }

    func delete(_ bookmark: Bookmark, in context: ModelContext) {
        let bookId = bookmark.book?.id
        remember(bookmark.annotationID, editable: bookmark.isEditableOnServer, bookId: bookId)
        context.delete(bookmark)
        try? context.save()
        if let bookId { noteChanged(bookId: bookId) }
    }

    func setNote(_ text: String?, on highlight: Highlight, in context: ModelContext) {
        guard highlight.isEditableOnServer else { return }
        highlight.setNote(text)
        try? context.save()
        if let bookId = highlight.book?.id { noteChanged(bookId: bookId) }
    }

    /// Always remembered, even for a row never sent: a push carrying it may already be on the wire.
    private func remember(_ annotationID: String, editable: Bool, bookId: UUID?) {
        guard let bookId else { return }
        let key = editable ? Self.pendingDeletesKey : Self.forgottenKey
        var all = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        all[bookId.uuidString, default: []].append(annotationID)
        defaults.set(all, forKey: key)
    }

    private func ids(_ key: String, bookId: UUID) -> [String] {
        (defaults.dictionary(forKey: key) as? [String: [String]])?[bookId.uuidString] ?? []
    }

    private func clearPendingDeletes(_ sent: Set<String>, bookId: UUID) {
        var all = defaults.dictionary(forKey: Self.pendingDeletesKey) as? [String: [String]] ?? [:]
        let left = (all[bookId.uuidString] ?? []).filter { !sent.contains($0) }
        all[bookId.uuidString] = left.isEmpty ? nil : left
        defaults.set(all, forKey: Self.pendingDeletesKey)
    }

    // MARK: Running

    /// Syncs every book with a local change. One sync runs at a time, so two pushes for a book
    /// cannot reach the server out of order.
    func flush() async {
        await serialized {
            self.pushTimer?.cancel()
            self.pushTimer = nil
            let books = self.pendingBooks
            self.pendingBooks.removeAll()
            for bookId in books where !(await self.syncBook(bookId)) {
                self.pendingBooks.insert(bookId)
            }
        }
    }

    /// Syncs one book now: when it is opened, so annotations made in other readers are there.
    func sync(bookId: UUID) async {
        await serialized {
            if await self.syncBook(bookId) {
                self.pendingBooks.remove(bookId)
            } else {
                self.pendingBooks.insert(bookId)
            }
        }
    }

    @discardableResult
    func flushInBackground(application: any BackgroundTasking = UIApplication.shared) -> Task<Void, Never> {
        let assertion = BackgroundAssertion(application: application)
        assertion.begin(name: "annotation-sync")
        return Task {
            await flush()
            assertion.end()
        }
    }

    func serverSettingsChanged(_ server: OPDSServer) {
        let prefix = "\(server.id.uuidString)|"
        supportCache = supportCache.filter { !$0.key.hasPrefix(prefix) }
    }

    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = running
        let current = Task { @MainActor in
            await previous?.value
            await work()
        }
        running = current
        await current.value
    }

    // MARK: One book

    /// False only when the sync should be retried.
    private func syncBook(_ bookId: UUID) async -> Bool {
        guard let book = fetchBook(bookId), let target = syncTarget(for: book) else { return true }
        switch await supportsAnnotations(target.server) {
        case nil: return false
        case false?: return true
        case true?: break
        }
        let configuration = OPDSRequestConfiguration(target.server)
        let remote: [KOSyncRemoteAnnotation]?
        do {
            remote = try await client.annotations(of: target.key, on: configuration)
        } catch {
            Self.logger.error("Annotation pull failed: \(error.localizedDescription)")
            return false
        }
        // The server does not have this book: nothing to merge with and nowhere to send.
        guard let remote, fetchBook(bookId) != nil else { return true }
        await apply(remote, to: bookId)
        return await push(bookId, key: target.key, configuration: configuration)
    }

    private func apply(_ remote: [KOSyncRemoteAnnotation], to bookId: UUID) async {
        guard let book = fetchBook(bookId), let modelContext else { return }
        let forgotten = Set(ids(Self.forgottenKey, bookId: bookId) + ids(Self.pendingDeletesKey, bookId: bookId))
        let plan = AnnotationSyncLogic.plan(local: Self.locals(of: book), remote: remote, forgotten: forgotten)
        let now = Date()
        for id in plan.deleteLocal {
            if let highlight = book.highlights.first(where: { $0.id == id }) { modelContext.delete(highlight) }
            if let bookmark = book.bookmarks.first(where: { $0.id == id }) { modelContext.delete(bookmark) }
        }
        for update in plan.updateNote {
            guard let highlight = book.highlights.first(where: { $0.id == update.id }), !highlight.needsPush else { continue }
            highlight.note = update.note
            highlight.syncedAt = max(now, highlight.modifiedAt ?? highlight.createdAt)
        }
        if !plan.adopt.isEmpty {
            let text = book.extractedText, rows = plan.adopt
            let placed = await Task.detached {
                let prepared = AnchoredText(text)
                return rows.compactMap { row in
                    row.quote.flatMap { prepared.resolve($0, near: row.percentage) }.map { (row, $0) }
                }
            }.value
            if let book = fetchBook(bookId) { adopt(placed, into: book, in: modelContext) }
        }
        try? modelContext.save()
    }

    /// Another reader's annotations, placed in this copy. A row that cannot be placed is left on
    /// the server and tried again at the next sync.
    private func adopt(_ placed: [(KOSyncRemoteAnnotation, ClosedRange<Int>)], into book: Book, in context: ModelContext) {
        var known = Set(Self.locals(of: book).map { $0.annotationID.lowercased() })
        let words = book.words
        for (row, range) in placed where known.insert(row.annotationID.lowercased()).inserted {
            let start = ReadingPositionCoordinator.clampedIndex(range.lowerBound, wordCount: words.count)
            let end = ReadingPositionCoordinator.clampedIndex(range.upperBound, wordCount: words.count)
            switch AnnotationSyncLogic.kind(of: row) {
            case .bookmark?:
                let bookmark = Bookmark(wordIndex: start, previewText: Bookmark.previewText(from: words, at: start))
                bookmark.syncID = row.annotationID
                bookmark.syncSource = row.source ?? "unknown"
                bookmark.syncedAt = Date()
                bookmark.book = book
                context.insert(bookmark)
            case .highlight?:
                let highlight = Highlight(startWordIndex: start, endWordIndex: end,
                                          highlightedText: Highlight.captureText(from: words, start: start, end: end))
                highlight.syncID = row.annotationID
                highlight.syncSource = row.source ?? "unknown"
                highlight.note = row.note
                highlight.syncOriginDevice = row.deviceOriginID
                highlight.syncedAt = Date()
                highlight.book = book
                context.insert(highlight)
            case nil:
                continue
            }
        }
    }

    private struct Outgoing: Sendable {
        let id: UUID
        let annotationID: String
        let kind: AnnotationSyncLogic.Kind
        let start: Int
        let end: Int
        let note: String?
        /// The device that made it, when that was not this one.
        let origin: String?
        /// The change being sent; a later one is still unsent after this push.
        let stamp: Date
    }

    private func push(_ bookId: UUID, key: String, configuration: OPDSRequestConfiguration) async -> Bool {
        guard let book = fetchBook(bookId) else { return true }
        let deletes = ids(Self.pendingDeletesKey, bookId: bookId)
        let outgoing = book.highlights.filter(\.needsPush).map {
            Outgoing(id: $0.id, annotationID: $0.annotationID, kind: .highlight, start: $0.startWordIndex,
                     end: $0.endWordIndex, note: $0.note, origin: $0.syncOriginDevice,
                     stamp: $0.modifiedAt ?? $0.createdAt)
        } + book.bookmarks.filter(\.needsPush).map {
            Outgoing(id: $0.id, annotationID: $0.annotationID, kind: .bookmark, start: $0.wordIndex,
                     end: $0.wordIndex, note: nil, origin: nil, stamp: $0.createdAt)
        }
        guard !outgoing.isEmpty || !deletes.isEmpty else { return true }

        let text = book.extractedText, wordCount = book.wordCount, thisDevice = deviceID
        let rows: [(UUID, KOSyncAnnotationPush.Row?)] = await Task.detached {
            let prepared = AnchoredText(text)
            return outgoing.map { item in
                let quote = prepared.quote(fromToken: item.start, toToken: item.end)?.wireSafe()
                return (item.id, quote.map {
                    KOSyncAnnotationPush.Row(
                        annotationID: item.annotationID, type: item.kind == .bookmark ? .dogear : .highlight,
                        quote: $0, percentage: AnnotationSyncLogic.percentage(token: item.start, wordCount: wordCount),
                        note: item.note, deviceOriginID: item.origin ?? thisDevice)
                })
            }
        }.value
        let payload = KOSyncAnnotationPush(document: key, device: deviceName, deviceID: deviceID,
                                           annotations: rows.compactMap(\.1), deleted: deletes)
        let result: KOSyncAnnotationPushResult
        do {
            result = try await client.push(payload, to: configuration)
        } catch {
            Self.logger.error("Annotation push failed: \(error.localizedDescription)")
            return false
        }
        guard result.matched else { return true }
        clearPendingDeletes(Set(deletes), bookId: bookId)
        // A row that cannot be quoted is marked too: it would never be sendable, so retrying it
        // forever would only repeat this request.
        let now = Date()
        for item in outgoing {
            if let highlight = fetchBook(bookId)?.highlights.first(where: { $0.id == item.id }),
               (highlight.modifiedAt ?? highlight.createdAt) == item.stamp {
                highlight.syncedAt = max(now, item.stamp)
            }
            if let bookmark = fetchBook(bookId)?.bookmarks.first(where: { $0.id == item.id }) {
                bookmark.syncedAt = max(now, item.stamp)
            }
        }
        try? modelContext?.save()
        return true
    }

    // MARK: Servers

    private static func locals(of book: Book) -> [AnnotationSyncLogic.Local] {
        book.highlights.map {
            .init(id: $0.id, annotationID: $0.annotationID, kind: .highlight, note: $0.note, needsPush: $0.needsPush)
        } + book.bookmarks.map {
            .init(id: $0.id, annotationID: $0.annotationID, kind: .bookmark, note: nil, needsPush: $0.needsPush)
        }
    }

    private func fetchBook(_ bookId: UUID) -> Book? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        return try? modelContext.fetch(descriptor).first
    }

    /// The server this book syncs with and the key it knows the book by, or nil when the book did
    /// not come from a server or that server's sync is off. One switch covers position and
    /// annotations: they are the same promise to the reader.
    private func syncTarget(for book: Book) -> (server: OPDSServer, key: String)? {
        guard let modelContext, let origin = book.origin else { return nil }
        let serverID = origin.serverID
        let descriptor = FetchDescriptor<OPDSServer>(predicate: #Predicate { $0.id == serverID })
        guard let server = try? modelContext.fetch(descriptor).first, server.syncsReadingPosition,
              let key = AnnotationSyncLogic.documentKey(digest: book.sourceDigest, origin: origin, serverID: server.id)
        else { return nil }
        return (server, key)
    }

    /// Nil when the server could not be asked, so the caller retries.
    private func supportsAnnotations(_ server: OPDSServer) async -> Bool? {
        let key = "\(server.id.uuidString)|\(server.baseURLString)|\(server.username)"
        if let cached = supportCache[key] { return cached }
        do {
            let supported = try await client.capabilities(of: OPDSRequestConfiguration(server))
                .contains(KOSyncWire.textQuoteAnnotationsCapability)
            supportCache[key] = supported
            return supported
        } catch {
            Self.logger.error("Annotation support probe failed: \(error.localizedDescription)")
            return nil
        }
    }
}
