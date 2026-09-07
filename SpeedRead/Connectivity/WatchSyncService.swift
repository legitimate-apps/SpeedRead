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

        init(
            bookId: UUID,
            bookTitle: String,
            wordIndex: Int,
            timestamp: Date,
            furthestReadWordIndex: Int = 0,
            didFinish: Bool = false,
            finishedAt: Date? = nil
        ) {
            self.bookId = bookId
            self.bookTitle = bookTitle
            self.wordIndex = wordIndex
            self.timestamp = timestamp
            self.furthestReadWordIndex = furthestReadWordIndex
            self.didFinish = didFinish
            self.finishedAt = finishedAt
        }

        var dictionary: [String: Any] {
            var dictionary: [String: Any] = [
                "bookId": bookId.uuidString,
                "bookTitle": bookTitle,
                "wordIndex": wordIndex,
                "timestamp": timestamp.timeIntervalSince1970,
                "furthestReadWordIndex": furthestReadWordIndex,
                "didFinish": didFinish
            ]
            if didFinish, let finishedAt {
                dictionary["finishedAt"] = finishedAt.timeIntervalSince1970
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
                finishedAt: finishedAt
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

    static func shouldOfferWatchPosition(
        incoming: PositionPayload,
        localIndex: Int,
        localDate: Date?,
        wordCount: Int,
        pendingOfferDate: Date? = nil,
        localHasFinished: Bool = false,
        pendingOfferDidFinish: Bool? = nil
    ) -> Bool {
        if let pendingOfferDate, incoming.timestamp <= pendingOfferDate { return false }
        guard wordCount > 0,
              reconcile(
                incoming: incoming,
                bookExists: true,
                lastReadDate: localDate
              ) == .apply else {
            return false
        }
        let clampedIncoming = ReadingPositionCoordinator.clampedIndex(incoming.wordIndex, wordCount: wordCount)
        let materialDifference = max(5, Int(ceil(Double(wordCount) * 0.01)))
        let incomingFinishes = ReadingPositionCoordinator.completionDate(
            didFinish: incoming.didFinish, index: clampedIncoming, wordCount: wordCount,
            existingDate: nil, incomingDate: incoming.finishedAt, now: incoming.timestamp
        ) != nil
        // A completion change is material even at the same final word. A newer commit
        // must also replace an opposite-completion offer that has not been accepted yet.
        return abs(clampedIncoming - localIndex) >= materialDifference
            || incomingFinishes != localHasFinished
            || pendingOfferDidFinish.map { $0 != incomingFinishes } == true
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
    struct PositionOffer: Equatable, Identifiable {
        var id: UUID { bookId }
        let bookId: UUID
        let bookTitle: String
        let wordIndex: Int
        let wordCount: Int
        let timestamp: Date
        var didFinish: Bool = false
        var finishedAt: Date? = nil

        var displayText: String {
            let isFinished = ReadingPositionCoordinator.completionDate(
                didFinish: didFinish, index: wordIndex, wordCount: wordCount,
                existingDate: nil, incomingDate: finishedAt, now: timestamp
            ) != nil
            let percentage = isFinished ? 100 : wordCount > 0
                ? Int((Double(wordIndex) / Double(wordCount) * 100).rounded())
                : 0
            return "Continue from Apple Watch — \(percentage)%, word \((wordIndex + 1).formatted())"
        }
    }

    enum SendState: Equatable {
        case idle
        case sending(String)
        case sent(String)
        case failed(String)
    }

    @Published var sendState: SendState = .idle
    @Published private(set) var pendingWatchPositionOffer: PositionOffer?
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

    #if os(iOS) && DEBUG
    // Lets unit tests exercise acceptance independently of the ingress clamp.
    convenience init(session: any WatchConnectivitySession, pendingOffer: PositionOffer) {
        self.init(session: session)
        pendingWatchPositionOffer = pendingOffer
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
    @MainActor
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

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
        let payload = WatchSyncLogic.PositionPayload(
            bookId: bookId,
            bookTitle: bookTitle,
            wordIndex: wordIndex,
            timestamp: timestamp,
            furthestReadWordIndex: outgoingFurthest,
            didFinish: outgoingDidFinish,
            finishedAt: outgoingFinishedAt
        )
        try? connectivitySession.updateApplicationContext(payload.dictionary)
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
                wordCount: legacy.text.split(whereSeparator: \.isWhitespace).count,
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
        Task { @MainActor [weak self] in
            #if os(watchOS)
            guard let self else { return }
            guard let book = self.library.books.first(where: { $0.id == payload.bookId }) else { return }
            let readingDecision = WatchSyncLogic.reconcile(
                incoming: payload,
                bookExists: true,
                lastReadDate: book.lastReadDate
            )
            let mergedFurthest = WatchSyncLogic.mergedFurthestRead(
                local: book.furthestReadWordIndex,
                incoming: payload.furthestReadWordIndex
            )
            var changed = self.library.mergeFurthestReadPosition(
                bookId: payload.bookId,
                index: mergedFurthest
            )
            if readingDecision == .apply {
                changed = self.library.updatePosition(
                    bookId: payload.bookId,
                    index: payload.wordIndex,
                    timestamp: payload.timestamp,
                    furthestReadWordIndex: mergedFurthest,
                    didFinish: payload.didFinish,
                    finishedAt: payload.finishedAt
                ) || changed
            }
            if changed { self.persistLibrary() }
            #elseif os(iOS)
            self?.applyIncomingPosition(payload)
            #endif
        }
    }

    #if os(iOS)
    @MainActor
    func applyIncomingPosition(_ payload: WatchSyncLogic.PositionPayload) {
        guard let modelContext else { return }
        let bookId = payload.bookId
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        guard let book = try? modelContext.fetch(descriptor).first else { return }
        book.ensurePositionMarkersInitialized()
        let clampedIndex = ReadingPositionCoordinator.clampedIndex(payload.wordIndex, wordCount: book.wordCount)
        book.furthestReadWordIndex = ReadingPositionCoordinator.clampedIndex(
            WatchSyncLogic.mergedFurthestRead(
                local: book.furthestReadWordIndex,
                incoming: payload.furthestReadWordIndex
            ),
            wordCount: book.wordCount
        )
        if WatchSyncLogic.shouldOfferWatchPosition(
            incoming: payload,
            localIndex: book.lastReadWordIndex,
            localDate: book.lastReadDate,
            wordCount: book.wordCount,
            pendingOfferDate: pendingWatchPositionOffer?.bookId == book.id
                ? pendingWatchPositionOffer?.timestamp : nil,
            localHasFinished: book.finishedAt != nil,
            pendingOfferDidFinish: pendingWatchPositionOffer?.bookId == book.id
                ? pendingWatchPositionOffer?.didFinish : nil
        ) {
            pendingWatchPositionOffer = PositionOffer(
                bookId: book.id,
                bookTitle: book.title,
                wordIndex: clampedIndex,
                wordCount: book.wordCount,
                timestamp: payload.timestamp,
                didFinish: ReadingPositionCoordinator.completionDate(
                    didFinish: payload.didFinish, index: clampedIndex, wordCount: book.wordCount,
                    existingDate: nil, incomingDate: payload.finishedAt, now: payload.timestamp
                ) != nil,
                finishedAt: payload.finishedAt
            )
        }
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to persist watch reading position: \(error.localizedDescription)")
        }
    }

    @MainActor
    func dismissWatchPositionOffer() {
        pendingWatchPositionOffer = nil
    }

    @MainActor
    @discardableResult
    func continueFromWatch(_ offer: PositionOffer) -> Bool {
        guard pendingWatchPositionOffer == offer,
              let modelContext else { return false }
        let bookId = offer.bookId
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        guard let book = try? modelContext.fetch(descriptor).first else {
            pendingWatchPositionOffer = nil
            return false
        }
        let acceptedIndex = ReadingPositionCoordinator.clampedIndex(offer.wordIndex, wordCount: book.wordCount)
        let payload = WatchSyncLogic.PositionPayload(
            bookId: offer.bookId,
            bookTitle: offer.bookTitle,
            wordIndex: acceptedIndex,
            timestamp: offer.timestamp
        )
        guard WatchSyncLogic.reconcile(
            incoming: payload,
            bookExists: true,
            lastReadDate: book.lastReadDate
        ) == .apply else {
            pendingWatchPositionOffer = nil
            return false
        }
        book.ensurePositionMarkersInitialized()
        book.lastReadWordIndex = acceptedIndex
        book.finishedAt = ReadingPositionCoordinator.completionDate(
            didFinish: offer.didFinish, index: acceptedIndex, wordCount: book.wordCount,
            existingDate: book.finishedAt, incomingDate: offer.finishedAt, now: offer.timestamp
        )
        book.lastReadDate = offer.timestamp
        book.browseWordIndex = acceptedIndex
        book.furthestReadWordIndex = ReadingPositionCoordinator.clampedIndex(
            WatchSyncLogic.mergedFurthestRead(
                local: book.furthestReadWordIndex,
                incoming: acceptedIndex
            ),
            wordCount: book.wordCount
        )
        do {
            try modelContext.save()
            pendingWatchPositionOffer = nil
            return true
        } catch {
            Self.logger.error("Failed to persist accepted watch reading position: \(error.localizedDescription)")
            return false
        }
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
