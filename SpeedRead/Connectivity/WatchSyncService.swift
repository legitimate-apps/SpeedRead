import Combine
import Foundation
import SwiftData
import WatchConnectivity
import os
#if os(watchOS)
import WatchKit
#endif

protocol WatchConnectivitySession: AnyObject {
    associatedtype Transfer

    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }
    #if os(iOS)
    var isPaired: Bool { get }
    #endif
    var delegate: (any WCSessionDelegate)? { get set }

    func activate()
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )
    func transferFile(_ fileURL: URL, metadata: [String: Any]?) -> Transfer
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

extension WCSession: WatchConnectivitySession {}

struct WatchSyncLogic {
    nonisolated struct BookPayload: Equatable, Sendable {
        let id: UUID
        let title: String
        let author: String
        let text: String
        let wordCount: Int
        let chapters: [ChapterMark]

        init(
            id: UUID,
            title: String,
            author: String,
            text: String,
            wordCount: Int,
            chapters: [ChapterMark] = []
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.text = text
            self.wordCount = wordCount
            self.chapters = chapters
        }

        private var chapterDictionaries: [[String: Any]] {
            chapters.map {
                ["title": $0.title, "startWordIndex": $0.startWordIndex]
            }
        }

        var dictionary: [String: Any] {
            [
                "id": id.uuidString,
                "title": title,
                "author": author,
                "text": text,
                "wordCount": wordCount,
                "chapters": chapterDictionaries
            ]
        }

        var fileMetadata: [String: Any] {
            [
                "id": id.uuidString,
                "title": title,
                "author": author,
                "wordCount": wordCount,
                "chapters": chapterDictionaries
            ]
        }

        static func decode(from dictionary: [String: Any], inlineText: String? = nil) -> BookPayload? {
            guard let idString = dictionary["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = dictionary["title"] as? String,
                  let author = dictionary["author"] as? String,
                  let text = inlineText ?? (dictionary["text"] as? String) else {
                return nil
            }
            let wordCount = (dictionary["wordCount"] as? Int)
                ?? text.split(whereSeparator: \.isWhitespace).count
            guard wordCount >= 0 else { return nil }
            let chapters: [ChapterMark]
            if let encodedChapters = dictionary["chapters"] as? [[String: Any]] {
                var decoded: [ChapterMark] = []
                for encoded in encodedChapters {
                    guard let chapterTitle = encoded["title"] as? String,
                          !chapterTitle.isEmpty,
                          let startWordIndex = encoded["startWordIndex"] as? Int,
                          startWordIndex >= 0,
                          startWordIndex < wordCount else {
                        return nil
                    }
                    decoded.append(ChapterMark(
                        title: chapterTitle,
                        startWordIndex: startWordIndex
                    ))
                }
                chapters = decoded
            } else if dictionary["chapters"] == nil {
                chapters = []
            } else {
                return nil
            }
            return BookPayload(
                id: id,
                title: title,
                author: author,
                text: text,
                wordCount: wordCount,
                chapters: chapters
            )
        }
    }

    nonisolated struct PositionPayload: Equatable, Sendable {
        let bookId: UUID
        let bookTitle: String
        let wordIndex: Int
        let timestamp: Date
        let furthestReadWordIndex: Int
        let didFinish: Bool
        let finishedAt: Date?
        /// The place: the word on screen, moved by any interaction. Last-write-wins on
        /// `browseTimestamp`, separately from the reading position above.
        let browseWordIndex: Int
        let browseTimestamp: Date
        /// The sender is reading this book right now, in a run that began at `playStartedAt`.
        let isPlaying: Bool
        let playStartedAt: Date?
        let sentAt: Date

        init(
            bookId: UUID,
            bookTitle: String,
            wordIndex: Int,
            timestamp: Date,
            furthestReadWordIndex: Int = 0,
            didFinish: Bool = false,
            finishedAt: Date? = nil,
            browseWordIndex: Int? = nil,
            browseTimestamp: Date? = nil,
            isPlaying: Bool = false,
            playStartedAt: Date? = nil,
            sentAt: Date? = nil
        ) {
            self.bookId = bookId
            self.bookTitle = bookTitle
            self.wordIndex = wordIndex
            self.timestamp = timestamp
            self.furthestReadWordIndex = furthestReadWordIndex
            self.didFinish = didFinish
            self.finishedAt = finishedAt
            self.browseWordIndex = browseWordIndex ?? wordIndex
            self.browseTimestamp = browseTimestamp ?? timestamp
            self.isPlaying = isPlaying
            self.playStartedAt = playStartedAt
            self.sentAt = sentAt ?? timestamp
        }

        /// The same book state with the place moved: a heartbeat's live word.
        func movingPlace(to index: Int, at date: Date) -> PositionPayload {
            PositionPayload(
                bookId: bookId, bookTitle: bookTitle, wordIndex: wordIndex, timestamp: timestamp,
                furthestReadWordIndex: furthestReadWordIndex, didFinish: didFinish,
                finishedAt: finishedAt, browseWordIndex: index, browseTimestamp: date,
                isPlaying: isPlaying, playStartedAt: playStartedAt, sentAt: sentAt
            )
        }

        /// The same place, stamped with this device's live state at the moment of sending.
        func stamped(isPlaying: Bool, playStartedAt: Date?, sentAt: Date) -> PositionPayload {
            PositionPayload(
                bookId: bookId, bookTitle: bookTitle, wordIndex: wordIndex, timestamp: timestamp,
                furthestReadWordIndex: furthestReadWordIndex, didFinish: didFinish,
                finishedAt: finishedAt, browseWordIndex: browseWordIndex,
                browseTimestamp: browseTimestamp, isPlaying: isPlaying,
                playStartedAt: isPlaying ? playStartedAt : nil, sentAt: sentAt
            )
        }

        var dictionary: [String: Any] {
            var dictionary: [String: Any] = [
                "bookId": bookId.uuidString,
                "bookTitle": bookTitle,
                "wordIndex": wordIndex,
                "timestamp": timestamp.timeIntervalSince1970,
                "furthestReadWordIndex": furthestReadWordIndex,
                "didFinish": didFinish,
                "browseWordIndex": browseWordIndex,
                "browseTimestamp": browseTimestamp.timeIntervalSince1970,
                "isPlaying": isPlaying,
                "sentAt": sentAt.timeIntervalSince1970
            ]
            if didFinish, let finishedAt {
                dictionary["finishedAt"] = finishedAt.timeIntervalSince1970
            }
            if isPlaying, let playStartedAt {
                dictionary["playStartedAt"] = playStartedAt.timeIntervalSince1970
            }
            return dictionary
        }

        static func decode(from dictionary: [String: Any]) -> PositionPayload? {
            guard let idString = dictionary["bookId"] as? String,
                  let bookId = UUID(uuidString: idString),
                  let bookTitle = dictionary["bookTitle"] as? String,
                  let wordIndex = dictionary["wordIndex"] as? Int,
                  wordIndex >= 0,
                  let interval = dictionary["timestamp"] as? TimeInterval,
                  interval.isFinite else {
                return nil
            }
            let didFinish = (dictionary["didFinish"] as? Bool) ?? false
            let completionInterval = dictionary["finishedAt"] as? TimeInterval
            let finishedAt = completionInterval.flatMap {
                didFinish && $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
            }
            let browseWordIndex = (dictionary["browseWordIndex"] as? Int) ?? wordIndex
            guard browseWordIndex >= 0 else { return nil }
            func date(_ key: String) -> Date? {
                (dictionary[key] as? TimeInterval).flatMap {
                    $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
                }
            }
            let isPlaying = (dictionary["isPlaying"] as? Bool) ?? false
            return PositionPayload(
                bookId: bookId,
                bookTitle: bookTitle,
                wordIndex: wordIndex,
                timestamp: Date(timeIntervalSince1970: interval),
                furthestReadWordIndex: max(
                    0,
                    (dictionary["furthestReadWordIndex"] as? Int) ?? wordIndex
                ),
                didFinish: didFinish,
                finishedAt: finishedAt,
                browseWordIndex: browseWordIndex,
                browseTimestamp: date("browseTimestamp"),
                isPlaying: isPlaying,
                playStartedAt: isPlaying ? date("playStartedAt") : nil,
                sentAt: date("sentAt")
            )
        }
    }

    enum PositionDecision: Equatable {
        case apply
        case ignoreStale
        case ignoreUnknownBook
    }

    static func reconcile(
        incoming: PositionPayload,
        bookExists: Bool,
        lastReadDate: Date?
    ) -> PositionDecision {
        guard bookExists else { return .ignoreUnknownBook }
        guard let lastReadDate else { return .apply }
        return incoming.timestamp > lastReadDate ? .apply : .ignoreStale
    }

    static func mergedFurthestRead(local: Int, incoming: Int) -> Int {
        max(local, incoming)
    }

    enum BookDeliveryRoute: Equatable {
        case message
        case file
    }

    static func initialBookDeliveryRoute(isReachable: Bool) -> BookDeliveryRoute {
        isReachable ? .message : .file
    }

    static func bookDeliveryRouteAfterMessageFailure() -> BookDeliveryRoute {
        .file
    }
}

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    nonisolated private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "WatchSync")
    private let connectivitySession: any WatchConnectivitySession

    /// The other device is reading a book right now. Drives the "Reading on …" card.
    @Published private(set) var remotePresence: RemotePresence?
    private var localRun: LocalRun?
    private var heartbeatTask: Task<Void, Never>?
    private var presenceExpiryTask: Task<Void, Never>?
    private var pendingPlace: WatchSyncLogic.PositionPayload?
    private var placeFlushTask: Task<Void, Never>?
    private var lastLivePersist: Date = .distantPast
    private var pendingPersistTask: Task<Void, Never>?
    /// Per book, when the other device last said it was not playing. A heartbeat sent before
    /// that (a message can arrive after the context that followed it) belongs to a released run.
    private var releasedAt: [UUID: Date] = [:]
    var clock: () -> Date = { Date() }
    var heartbeatInterval = LiveHandoffLogic.heartbeatInterval
    var placeCoalescing = LiveHandoffLogic.placeCoalescing
    var livePersistInterval = LiveHandoffLogic.livePersistInterval

    #if os(watchOS)
    @Published var library: WatchLibrary = .empty
    var currentBook: WatchBook? { library.currentBook }

    @Published var isReceiving = false
    @Published var receivingTitle: String?
    #if DEBUG
    private var debugPositionSyncTask: Task<Void, Never>?
    #endif
    #endif

    #if os(iOS)
    enum SendState: Equatable {
        case idle
        case sending(String)
        case sent(String)
        case failed(String)
    }

    @Published var sendState: SendState = .idle
    private var sendStateClearTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    #endif

    #if os(watchOS)
    private let libraryStore: WatchLibraryStore
    private var legacyBookURL: URL {
        libraryStore.fileURL.deletingLastPathComponent().appendingPathComponent("watchbook.json")
    }

    init(
        session: any WatchConnectivitySession = WCSession.default,
        store: WatchLibraryStore? = nil
    ) {
        connectivitySession = session
        libraryStore = store ?? WatchLibraryStore(
            fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("watchlibrary.json")
        )
        super.init()
    }
    #else
    init(session: any WatchConnectivitySession = WCSession.default) {
        connectivitySession = session
        super.init()
    }
    #endif

    func activate() {
        #if os(watchOS)
        loadLibrary()
        #endif
        guard WCSession.isSupported() else {
            Self.logger.warning("WCSession not supported on this device")
            return
        }
        Self.logger.info("Activating WCSession")
        connectivitySession.delegate = self
        connectivitySession.activate()
        #if os(watchOS) && DEBUG
        scheduleDebugPositionSyncIfRequested()
        #endif
    }

    #if os(watchOS) && DEBUG
    private func scheduleDebugPositionSyncIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let indexFlag = arguments.firstIndex(of: "--debug-sync-position-index"),
              arguments.indices.contains(indexFlag + 1),
              let wordIndex = Int(arguments[indexFlag + 1]),
              let timestampFlag = arguments.firstIndex(of: "--debug-sync-position-timestamp"),
              arguments.indices.contains(timestampFlag + 1),
              let interval = TimeInterval(arguments[timestampFlag + 1]) else { return }

        debugPositionSyncTask?.cancel()
        debugPositionSyncTask = Task { @MainActor [weak self] in
            for _ in 0..<100 {
                guard !Task.isCancelled else { return }
                if let book = self?.library.currentBook ?? self?.library.books.first {
                    self?.syncReadingPosition(
                        bookId: book.id,
                        bookTitle: book.title,
                        wordIndex: wordIndex,
                        timestamp: Date(timeIntervalSince1970: interval)
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    #endif

    // MARK: - Payload

    typealias BookPayload = WatchSyncLogic.BookPayload

    // MARK: - iPhone → Watch

    #if os(iOS)
    func sendBook(
        id: UUID,
        title: String,
        author: String,
        text: String,
        wordCount: Int,
        chapters: [ChapterMark] = []
    ) {
        guard connectivitySession.activationState == .activated else {
            sendState = .failed("Watch not connected")
            scheduleSendStateClear()
            return
        }

        let payload = BookPayload(
            id: id,
            title: title,
            author: author,
            text: text,
            wordCount: wordCount,
            chapters: chapters
        )
        sendState = .sending(title)

        Self.logger.info("Sending '\(title, privacy: .public)' — reachable=\(self.connectivitySession.isReachable) paired=\(self.connectivitySession.isPaired)")

        if WatchSyncLogic.initialBookDeliveryRoute(isReachable: connectivitySession.isReachable) == .message {
            connectivitySession.sendMessage(payload.dictionary, replyHandler: { @Sendable [weak self] reply in
                Self.logger.debug("sendMessage reply: \(reply)")
                let accepted = reply["status"] as? String == "ok"
                Task { @MainActor [weak self] in
                    if accepted {
                        self?.sendState = .sent(title)
                    } else {
                        self?.sendState = .failed("Apple Watch did not accept the book.")
                    }
                    self?.scheduleSendStateClear()
                }
            }, errorHandler: { @Sendable [weak self] error in
                Self.logger.warning("sendMessage failed: \(error.localizedDescription) — falling back to transferFile")
                Task { @MainActor [weak self] in
                    self?.fallbackToFileTransfer(payload: payload)
                }
            })
        } else {
            Self.logger.info("Watch not reachable, using transferFile")
            fallbackToFileTransfer(payload: payload)
        }
    }

    private func fallbackToFileTransfer(payload: BookPayload) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try payload.text.write(to: tempURL, atomically: true, encoding: .utf8)
            _ = connectivitySession.transferFile(tempURL, metadata: payload.fileMetadata)
        } catch {
            Self.logger.error("transferFile prep failed: \(error.localizedDescription)")
            sendState = .failed("Failed to prepare book")
            scheduleSendStateClear()
        }
    }

    private func scheduleSendStateClear() {
        sendStateClearTask?.cancel()
        sendStateClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            self?.sendState = .idle
        }
    }
    #endif

    // MARK: - Bidirectional Position Sync

    func syncReadingPosition(
        bookId: UUID,
        bookTitle: String,
        wordIndex: Int,
        timestamp: Date = Date(),
        didFinish: Bool = false,
        finishedAt: Date? = nil
    ) {
        syncReadingPosition(
            bookId: bookId,
            bookTitle: bookTitle,
            wordIndex: wordIndex,
            timestamp: timestamp,
            furthestReadWordIndex: wordIndex,
            didFinish: didFinish,
            finishedAt: finishedAt
        )
    }

    func syncReadingPosition(
        bookId: UUID,
        bookTitle: String,
        wordIndex: Int,
        timestamp: Date,
        furthestReadWordIndex: Int,
        didFinish: Bool = false,
        finishedAt: Date? = nil
    ) {
        var outgoingFurthest = furthestReadWordIndex
        var outgoingDidFinish = didFinish
        var outgoingFinishedAt = finishedAt
        #if os(watchOS)
        library.updatePosition(
            bookId: bookId,
            index: wordIndex,
            timestamp: timestamp,
            furthestReadWordIndex: furthestReadWordIndex,
            didFinish: didFinish,
            finishedAt: finishedAt
        )
        if let book = library.books.first(where: { $0.id == bookId }) {
            outgoingFurthest = book.furthestReadWordIndex
            outgoingDidFinish = book.hasFinishedLocally
            outgoingFinishedAt = book.finishedAt
        }
        persistLibrary()
        #endif
        guard connectivitySession.activationState == .activated else { return }
        send(WatchSyncLogic.PositionPayload(
            bookId: bookId,
            bookTitle: bookTitle,
            wordIndex: wordIndex,
            timestamp: timestamp,
            furthestReadWordIndex: outgoingFurthest,
            didFinish: outgoingDidFinish,
            finishedAt: outgoingFinishedAt
        ))
    }

    // MARK: - Live handoff

    /// This device is reading `bookId`. `snapshot` supplies the live place for heartbeats;
    /// `onYield` runs when the other device takes the book over.
    struct LocalRun {
        let bookId: UUID
        let startedAt: Date
        let snapshot: () -> WatchSyncLogic.PositionPayload?
        let onYield: (RemotePresence) -> Void
    }

    var localRunBookId: UUID? { localRun?.bookId }

    /// The other device's presence on `bookId`, when this device is not reading it itself.
    func remotePresence(for bookId: UUID?) -> RemotePresence? {
        guard let bookId,
              let remotePresence,
              remotePresence.bookId == bookId,
              localRun?.bookId != bookId else { return nil }
        return remotePresence
    }

    func beginLocalRun(
        bookId: UUID,
        snapshot: @escaping () -> WatchSyncLogic.PositionPayload?,
        onYield: @escaping (RemotePresence) -> Void
    ) {
        localRun = LocalRun(bookId: bookId, startedAt: clock(), snapshot: snapshot, onYield: onYield)
        Self.logger.debug("handoff: run began \(bookId, privacy: .public)")
        // Reading here is the takeover: the other device yields when it hears the heartbeat.
        if remotePresence?.bookId == bookId { clearPresence() }
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sendHeartbeat()
                guard let interval = self?.heartbeatInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Ends this device's run. Sends nothing: every path that ends a run by choice commits,
    /// and that commit carries the release; a yield must not answer the device that took over.
    func endLocalRun(bookId: UUID) {
        guard localRun?.bookId == bookId else { return }
        localRun = nil
        Self.logger.debug("handoff: run ended \(bookId, privacy: .public)")
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Heartbeats are live-only: a context saying "playing" would outlive the run.
    func sendHeartbeat() {
        guard let run = localRun,
              let payload = run.snapshot(),
              connectivitySession.activationState == .activated,
              connectivitySession.isReachable else { return }
        connectivitySession.sendMessage(stamp(payload).dictionary, replyHandler: nil, errorHandler: nil)
    }

    /// A browse move (crown, scrub, chapter jump). Coalesced to the latest move.
    func publishPlace(_ payload: WatchSyncLogic.PositionPayload) {
        pendingPlace = payload
        guard placeFlushTask == nil else { return }
        placeFlushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.placeCoalescing ?? .zero)
            self?.flushPendingPlace()
        }
    }

    func flushPendingPlace() {
        placeFlushTask?.cancel()
        placeFlushTask = nil
        guard let pendingPlace else { return }
        self.pendingPlace = nil
        send(pendingPlace)
    }

    private func send(_ payload: WatchSyncLogic.PositionPayload) {
        // A commit carries the newest place, so a coalesced move queued before it is moot.
        if pendingPlace?.bookId == payload.bookId, pendingPlace != payload {
            pendingPlace = nil
        }
        guard connectivitySession.activationState == .activated else { return }
        let dictionary = stamp(payload).dictionary
        try? connectivitySession.updateApplicationContext(dictionary)
        if connectivitySession.isReachable {
            connectivitySession.sendMessage(dictionary, replyHandler: nil, errorHandler: nil)
        }
    }

    private func stamp(_ payload: WatchSyncLogic.PositionPayload) -> WatchSyncLogic.PositionPayload {
        let isPlaying = localRun?.bookId == payload.bookId
        return payload.stamped(
            isPlaying: isPlaying,
            playStartedAt: isPlaying ? localRun?.startedAt : nil,
            sentAt: clock()
        )
    }

    /// Every incoming place, live or durable, from either delegate path.
    func receivePosition(_ payload: WatchSyncLogic.PositionPayload) {
        let now = clock()
        let keepsReading = updatePresence(from: payload, now: now)
        applyIncoming(payload, ownedHere: keepsReading, now: now)
    }

    /// Returns whether this device keeps reading the book, in which case the incoming place is
    /// an older run's and must not move it.
    private func updatePresence(from payload: WatchSyncLogic.PositionPayload, now: Date) -> Bool {
        if !payload.isPlaying {
            releasedAt[payload.bookId] = max(releasedAt[payload.bookId] ?? .distantPast, payload.sentAt)
        } else if let released = releasedAt[payload.bookId], payload.sentAt <= released {
            return false
        }
        guard let presence = LiveHandoffLogic.presence(from: payload, now: now) else {
            if let current = remotePresence,
               current.bookId == payload.bookId,
               !payload.isPlaying,
               payload.sentAt >= current.sentAt {
                clearPresence()
            }
            return false
        }
        if let run = localRun, run.bookId == presence.bookId {
            guard LiveHandoffLogic.shouldYield(
                localRunStartedAt: run.startedAt,
                incoming: presence,
                localDevice: .current
            ) else { return true }
            Self.logger.debug("handoff: yielding to the counterpart at word \(presence.wordIndex)")
            endLocalRun(bookId: run.bookId)
            run.onYield(presence)
        }
        if remotePresence?.playStartedAt != presence.playStartedAt {
            Self.logger.debug("handoff: counterpart is reading \(presence.bookId, privacy: .public)")
        }
        remotePresence = presence
        presenceExpiryTask?.cancel()
        let delay = max(0, LiveHandoffLogic.expiry(of: presence).timeIntervalSince(now))
        presenceExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.expirePresence(now: self.clock())
        }
        return false
    }

    /// The reading device went quiet (locked, out of range, killed): unlock at the last place.
    func expirePresence(now: Date) {
        guard let remotePresence,
              !LiveHandoffLogic.isLive(sentAt: remotePresence.sentAt, now: now) else { return }
        clearPresence()
    }

    private func clearPresence() {
        presenceExpiryTask?.cancel()
        presenceExpiryTask = nil
        guard remotePresence != nil else { return }
        remotePresence = nil
        persistLivePlace()
    }

    /// Reading persists at once. A place alone (a heartbeat, a scrub, a crown turn on the other
    /// device) persists at most once per interval, and a trailing write lands the latest.
    private func persistIncoming(readingMoved: Bool, now: Date) {
        let wait = readingMoved ? 0 : livePersistInterval - now.timeIntervalSince(lastLivePersist)
        guard wait > 0 else {
            pendingPersistTask?.cancel()
            pendingPersistTask = nil
            lastLivePersist = now
            persistLivePlace()
            return
        }
        guard pendingPersistTask == nil else { return }
        pendingPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.pendingPersistTask = nil
            self.lastLivePersist = self.clock()
            self.persistLivePlace()
        }
    }

    // MARK: - watchOS Persistence

    #if os(watchOS)
    private struct LegacyPersistedBook: Codable {
        let title: String
        let author: String
        let text: String
        var position: Int
    }

    func loadLibrary() {
        let persistedLibrary = libraryStore.load()
        if persistedLibrary != .empty || FileManager.default.fileExists(atPath: libraryStore.fileURL.path) {
            library = persistedLibrary
            return
        }
        if let data = try? Data(contentsOf: legacyBookURL),
           let legacy = try? JSONDecoder().decode(LegacyPersistedBook.self, from: data) {
            let book = WatchBook(
                id: UUID(), title: legacy.title, author: legacy.author, text: legacy.text,
                lastReadIndex: legacy.position, lastReadDate: nil,
                wordCount: BookTokenizer.tokenize(legacy.text).count,
                dateAdded: Date()
            )
            library = WatchLibrary(books: [book], currentBookId: book.id)
            persistLibrary()
            try? FileManager.default.removeItem(at: legacyBookURL)
        }
    }

    func persistLibrary() {
        do {
            try libraryStore.save(library)
        } catch {
            Self.logger.error("Failed to persist library: \(error.localizedDescription)")
        }
    }

    private func persistLivePlace() { persistLibrary() }

    private func applyIncoming(_ payload: WatchSyncLogic.PositionPayload, ownedHere: Bool, now: Date) {
        guard let book = library.books.first(where: { $0.id == payload.bookId }) else { return }
        let mergedFurthest = WatchSyncLogic.mergedFurthestRead(
            local: book.furthestReadWordIndex,
            incoming: payload.furthestReadWordIndex
        )
        var readingMoved = library.mergeFurthestReadPosition(bookId: payload.bookId, index: mergedFurthest)
        var placeMoved = false
        if !ownedHere {
            if WatchSyncLogic.reconcile(incoming: payload, bookExists: true,
                                        lastReadDate: book.lastReadDate) == .apply {
                readingMoved = library.updatePosition(
                    bookId: payload.bookId,
                    index: payload.wordIndex,
                    timestamp: payload.timestamp,
                    furthestReadWordIndex: mergedFurthest,
                    didFinish: payload.didFinish,
                    finishedAt: payload.finishedAt,
                    movesPlace: false
                ) || readingMoved
            }
            // A place never moved dates from the last read.
            if LiveHandoffLogic.shouldApplyPlace(localDate: book.browseDate ?? book.lastReadDate,
                                                 incomingDate: payload.browseTimestamp) {
                placeMoved = library.applyPlace(
                    bookId: payload.bookId,
                    index: payload.browseWordIndex,
                    date: payload.browseTimestamp
                )
            }
        }
        if readingMoved || placeMoved { persistIncoming(readingMoved: readingMoved, now: now) }
    }

    private func ingest(_ payload: BookPayload) {
        if library.books.contains(where: { $0.id == payload.id }) {
            WKInterfaceDevice.current().play(.click)
            isReceiving = false
            receivingTitle = nil
            return
        }
        let book = WatchBook(
            id: payload.id, title: payload.title, author: payload.author, text: payload.text,
            lastReadIndex: 0, lastReadDate: nil,
            wordCount: payload.wordCount, dateAdded: Date(), chapters: payload.chapters
        )
        library.addBook(book)
        persistLibrary()
        WKInterfaceDevice.current().play(.success)
        isReceiving = false
        receivingTitle = nil
    }
    #endif

    // MARK: - WCSessionDelegate

    // WatchConnectivity enters these Objective-C callbacks on its own queue.
    // Keep the entry points nonisolated; decode values here and hop to MainActor
    // before touching observable state or the injected session.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Self.logger.info("Activation completed: state=\(state.rawValue) error=\(error?.localizedDescription ?? "none", privacy: .public)")
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.connectivitySession.activate() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let title = fileTransfer.file.metadata?["title"] as? String ?? "Book"
        Task { @MainActor [weak self] in
            if let error {
                self?.sendState = .failed(error.localizedDescription)
            } else {
                self?.sendState = .sent(title)
            }
            self?.scheduleSendStateClear()
        }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = WatchSyncLogic.PositionPayload.decode(from: applicationContext) else { return }
        Task { @MainActor [weak self] in self?.receivePosition(payload) }
    }

    /// Live places arrive here: they are sent without a reply handler.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let payload = WatchSyncLogic.PositionPayload.decode(from: message) else { return }
        Task { @MainActor [weak self] in self?.receivePosition(payload) }
    }

    #if os(iOS)
    @MainActor
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func persistLivePlace() {
        do {
            try modelContext?.save()
        } catch {
            Self.logger.error("Failed to persist watch place: \(error.localizedDescription)")
        }
    }

    private func applyIncoming(_ payload: WatchSyncLogic.PositionPayload, ownedHere: Bool, now: Date) {
        guard let modelContext else { return }
        let bookId = payload.bookId
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        guard let book = try? modelContext.fetch(descriptor).first else { return }
        book.ensurePositionMarkersInitialized()
        book.furthestReadWordIndex = ReadingPositionCoordinator.clampedIndex(
            WatchSyncLogic.mergedFurthestRead(
                local: book.furthestReadWordIndex,
                incoming: payload.furthestReadWordIndex
            ),
            wordCount: book.wordCount
        )
        // A place never moved dates from the last read. Read before the reading marker moves.
        let localPlaceDate = book.browseDate ?? book.lastReadDate
        var readingMoved = false
        if !ownedHere {
            if WatchSyncLogic.reconcile(incoming: payload, bookExists: true,
                                        lastReadDate: book.lastReadDate) == .apply {
                let index = ReadingPositionCoordinator.clampedIndex(payload.wordIndex, wordCount: book.wordCount)
                book.lastReadWordIndex = index
                book.finishedAt = ReadingPositionCoordinator.completionDate(
                    didFinish: payload.didFinish, index: index, wordCount: book.wordCount,
                    existingDate: book.finishedAt, incomingDate: payload.finishedAt, now: payload.timestamp
                )
                book.lastReadDate = payload.timestamp
                readingMoved = true
            }
            if LiveHandoffLogic.shouldApplyPlace(localDate: localPlaceDate,
                                                 incomingDate: payload.browseTimestamp) {
                book.browseWordIndex = ReadingPositionCoordinator.clampedIndex(
                    payload.browseWordIndex, wordCount: book.wordCount
                )
                book.browseDate = payload.browseTimestamp
            }
        }
        persistIncoming(readingMoved: readingMoved, now: now)
        // Reading happened on the watch; the phone carries it to the library server.
        if readingMoved { ServerPositionSync.shared.noteCommitted(bookId: book.id) }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Self.logger.debug("didReceiveMessage keys: \(message.keys.sorted())")
        guard let payload = BookPayload.decode(from: message) else {
            replyHandler(["status": "error"])
            return
        }
        replyHandler(["status": "ok"])

        #if os(watchOS)
        Task { @MainActor [weak self] in
            self?.isReceiving = true
            self?.receivingTitle = payload.title
            self?.ingest(payload)
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Self.logger.debug("didReceive file with metadata: \(file.metadata ?? [:])")
        let metadata = file.metadata ?? [:]
        guard let text = try? String(contentsOf: file.fileURL, encoding: .utf8) else {
            #if os(watchOS)
            Task { @MainActor [weak self] in
                self?.isReceiving = false
                self?.receivingTitle = nil
            }
            #endif
            return
        }

        #if os(watchOS)
        let title = metadata["title"] as? String
        let payload = BookPayload.decode(from: metadata, inlineText: text)
        Task { @MainActor [weak self] in
            self?.isReceiving = true
            self?.receivingTitle = title
            guard let payload else {
                self?.isReceiving = false
                self?.receivingTitle = nil
                return
            }
            self?.ingest(payload)
        }
        #endif
    }
}
