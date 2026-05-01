import Combine
import Foundation
import WatchConnectivity
import os
#if os(watchOS)
import WatchKit
#endif

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

    /// Typed wrapper for the [String: Any] dictionary used by WCSession messages.
    struct BookPayload: Codable, Equatable {
        let id: UUID
        let title: String
        let author: String
        let text: String
        let wordCount: Int

        init(id: UUID, title: String, author: String, text: String, wordCount: Int) {
            self.id = id
            self.title = title
            self.author = author
            self.text = text
            self.wordCount = wordCount
        }

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

        /// Decodes from a [String: Any] payload. `text` may be nil when the body
        /// arrives via file transfer rather than inline message.
        static func decode(from dict: [String: Any], inlineText: String? = nil) -> BookPayload? {
            guard let title = dict["title"] as? String,
                  let author = dict["author"] as? String,
                  let text = inlineText ?? (dict["text"] as? String) else {
                return nil
            }
            let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            let wordCount = (dict["wordCount"] as? Int)
                ?? text.split(whereSeparator: \.isWhitespace).count
            return BookPayload(id: id, title: title, author: author, text: text, wordCount: wordCount)
        }
    }

    // MARK: - iPhone → Watch

    #if os(iOS)
    func sendBook(id: UUID, title: String, author: String, text: String, wordCount: Int) {
        guard WCSession.default.activationState == .activated else {
            sendState = .failed("Watch not connected")
            scheduleSendStateClear()
            return
        }

        let payload = BookPayload(id: id, title: title, author: author, text: text, wordCount: wordCount)
        sendState = .sending(title)

        Self.logger.info("Sending '\(title, privacy: .public)' — reachable=\(WCSession.default.isReachable) paired=\(WCSession.default.isPaired)")

        if WCSession.default.isReachable {
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

    func syncReadingPosition(bookId: UUID, bookTitle: String, wordIndex: Int) {
        #if os(watchOS)
        library.updatePosition(bookId: bookId, index: wordIndex)
        persistLibrary()
        #endif
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([
            "bookId": bookId.uuidString,
            "bookTitle": bookTitle,
            "wordIndex": wordIndex,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    // MARK: - watchOS Persistence

    #if os(watchOS)
    private static var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watchlibrary.json")
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
        if let data = try? Data(contentsOf: Self.libraryURL),
           let lib = try? JSONDecoder().decode(WatchLibrary.self, from: data) {
            library = lib
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
            let data = try JSONEncoder().encode(library)
            try data.write(to: Self.libraryURL, options: .atomic)
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
        #if os(watchOS)
        guard let bookIdStr = applicationContext["bookId"] as? String,
              let bookId = UUID(uuidString: bookIdStr),
              let index = applicationContext["wordIndex"] as? Int else { return }
        Task { @MainActor [weak self] in
            self?.library.updatePosition(bookId: bookId, index: index)
            self?.persistLibrary()
        }
        #endif
    }

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
