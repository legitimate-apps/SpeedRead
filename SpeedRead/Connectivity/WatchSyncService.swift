import Combine
import Foundation
import SwiftData
import WatchConnectivity
import os
#if os(watchOS)
import WatchKit
#endif

struct WatchSyncLogic {
    struct BookPayload: Equatable {
        let id: UUID
        let title: String
        let author: String
        let text: String
        let wordCount: Int

        var dictionary: [String: Any] {
            [
                "id": id.uuidString,
                "title": title,
                "author": author,
                "text": text,
                "wordCount": wordCount
            ]
        }

        var fileMetadata: [String: Any] {
            [
                "id": id.uuidString,
                "title": title,
                "author": author,
                "wordCount": wordCount
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
            return BookPayload(id: id, title: title, author: author, text: text, wordCount: wordCount)
        }
    }

    struct PositionPayload: Equatable {
        let bookId: UUID
        let bookTitle: String
        let wordIndex: Int
        let timestamp: Date

        var dictionary: [String: Any] {
            [
                "bookId": bookId.uuidString,
                "bookTitle": bookTitle,
                "wordIndex": wordIndex,
                "timestamp": timestamp.timeIntervalSince1970
            ]
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
            return PositionPayload(
                bookId: bookId,
                bookTitle: bookTitle,
                wordIndex: wordIndex,
                timestamp: Date(timeIntervalSince1970: interval)
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

    private static let logger = Logger(subsystem: "com.legitimateapps.SpeedRead", category: "WatchSync")

    #if os(watchOS)
    @Published var library: WatchLibrary = .empty
    var currentBook: WatchBook? { library.currentBook }

    @Published var isReceiving = false
    @Published var receivingTitle: String?
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

    private override init() {
        super.init()
    }

    func activate() {
        #if os(watchOS)
        loadLibrary()
        #endif
        guard WCSession.isSupported() else {
            Self.logger.warning("WCSession not supported on this device")
            return
        }
        Self.logger.info("Activating WCSession")
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Payload

    typealias BookPayload = WatchSyncLogic.BookPayload

    // MARK: - iPhone → Watch

    #if os(iOS)
    @MainActor
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func sendBook(id: UUID, title: String, author: String, text: String, wordCount: Int) {
        guard WCSession.default.activationState == .activated else {
            sendState = .failed("Watch not connected")
            scheduleSendStateClear()
            return
        }

        let payload = BookPayload(id: id, title: title, author: author, text: text, wordCount: wordCount)
        sendState = .sending(title)

        Self.logger.info("Sending '\(title, privacy: .public)' — reachable=\(WCSession.default.isReachable) paired=\(WCSession.default.isPaired)")

        if WatchSyncLogic.initialBookDeliveryRoute(isReachable: WCSession.default.isReachable) == .message {
            WCSession.default.sendMessage(payload.dictionary, replyHandler: { [weak self] reply in
                Self.logger.debug("sendMessage reply: \(reply)")
                Task { @MainActor [weak self] in
                    self?.sendState = .sent(title)
                    self?.scheduleSendStateClear()
                }
            }, errorHandler: { [weak self] error in
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
            WCSession.default.transferFile(tempURL, metadata: payload.fileMetadata)
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

    func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int, timestamp: Date = Date()) {
        #if os(watchOS)
        library.updatePosition(bookId: bookId, index: wordIndex, timestamp: timestamp)
        persistLibrary()
        #endif
        guard WCSession.default.activationState == .activated else { return }
        let payload = WatchSyncLogic.PositionPayload(
            bookId: bookId,
            bookTitle: bookTitle,
            wordIndex: wordIndex,
            timestamp: timestamp
        )
        try? WCSession.default.updateApplicationContext(payload.dictionary)
    }

    // MARK: - watchOS Persistence

    #if os(watchOS)
    private static var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watchlibrary.json")
    }

    private static var libraryStore: WatchLibraryStore {
        WatchLibraryStore(fileURL: libraryURL)
    }

    private static var legacyBookURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watchbook.json")
    }

    private struct LegacyPersistedBook: Codable {
        let title: String
        let author: String
        let text: String
        var position: Int
    }

    func loadLibrary() {
        let persistedLibrary = Self.libraryStore.load()
        if persistedLibrary != .empty || FileManager.default.fileExists(atPath: Self.libraryURL.path) {
            library = persistedLibrary
            return
        }
        if let data = try? Data(contentsOf: Self.legacyBookURL),
           let legacy = try? JSONDecoder().decode(LegacyPersistedBook.self, from: data) {
            let book = WatchBook(
                id: UUID(), title: legacy.title, author: legacy.author, text: legacy.text,
                lastReadIndex: legacy.position, lastReadDate: nil,
                wordCount: legacy.text.split(whereSeparator: \.isWhitespace).count,
                dateAdded: Date()
            )
            library = WatchLibrary(books: [book], currentBookId: book.id)
            persistLibrary()
            try? FileManager.default.removeItem(at: Self.legacyBookURL)
        }
    }

    func persistLibrary() {
        do {
            try Self.libraryStore.save(library)
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
            wordCount: payload.wordCount, dateAdded: Date()
        )
        library.addBook(book)
        persistLibrary()
        WKInterfaceDevice.current().play(.success)
        isReceiving = false
        receivingTitle = nil
    }
    #endif

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Self.logger.info("Activation completed: state=\(state.rawValue) error=\(error?.localizedDescription ?? "none", privacy: .public)")
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
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

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = WatchSyncLogic.PositionPayload.decode(from: applicationContext) else { return }
        Task { @MainActor [weak self] in
            #if os(watchOS)
            guard let self else { return }
            guard let book = self.library.books.first(where: { $0.id == payload.bookId }) else { return }
            guard WatchSyncLogic.reconcile(
                incoming: payload,
                bookExists: true,
                lastReadDate: book.lastReadDate
            ) == .apply else { return }
            self.library.updatePosition(
                bookId: payload.bookId,
                index: payload.wordIndex,
                timestamp: payload.timestamp
            )
            self.persistLibrary()
            #elseif os(iOS)
            self?.applyIncomingPosition(payload)
            #endif
        }
    }

    #if os(iOS)
    @MainActor
    private func applyIncomingPosition(_ payload: WatchSyncLogic.PositionPayload) {
        guard let modelContext else { return }
        let bookId = payload.bookId
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookId })
        guard let book = try? modelContext.fetch(descriptor).first else { return }
        guard WatchSyncLogic.reconcile(
            incoming: payload,
            bookExists: true,
            lastReadDate: book.lastReadDate
        ) == .apply else { return }
        book.lastReadWordIndex = min(payload.wordIndex, max(0, book.wordCount - 1))
        book.lastReadDate = payload.timestamp
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to persist watch reading position: \(error.localizedDescription)")
        }
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
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

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
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
        Task { @MainActor [weak self] in
            self?.isReceiving = true
            self?.receivingTitle = metadata["title"] as? String
            guard let payload = BookPayload.decode(from: metadata, inlineText: text) else {
                self?.isReceiving = false
                self?.receivingTitle = nil
                return
            }
            self?.ingest(payload)
        }
        #endif
    }
}
