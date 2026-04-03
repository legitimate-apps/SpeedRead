import Combine
import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncService()

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
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        #if os(watchOS)
        loadLibrary()
        #endif
        guard WCSession.isSupported() else {
            print("[WatchSync] WCSession NOT supported on this device")
            return
        }
        print("[WatchSync] Activating WCSession...")
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // iPhone -> Watch: send book text via transferFile
    #if os(iOS)
    func sendBook(id: UUID, title: String, author: String, text: String, wordCount: Int) {
        guard WCSession.default.activationState == .activated else {
            sendState = .failed("Watch not connected")
            clearSendStateAfterDelay()
            return
        }

        sendState = .sending(title)
        let message: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "author": author,
            "text": text,
            "wordCount": wordCount
        ]

        print("[WatchSync] Sending '\(title)' — isReachable=\(WCSession.default.isReachable) isPaired=\(WCSession.default.isPaired) activationState=\(WCSession.default.activationState.rawValue)")

        if WCSession.default.isReachable {
            print("[WatchSync] Using sendMessage...")
            WCSession.default.sendMessage(message, replyHandler: { reply in
                print("[WatchSync] sendMessage reply: \(reply)")
                DispatchQueue.main.async {
                    self.sendState = .sent(title)
                    self.clearSendStateAfterDelay()
                }
            }, errorHandler: { error in
                print("[WatchSync] sendMessage FAILED: \(error.localizedDescription) — falling back to transferFile")
                self.fallbackToFileTransfer(id: id, title: title, author: author, text: text, wordCount: wordCount)
            })
        } else {
            print("[WatchSync] Watch not reachable, using transferFile fallback...")
            fallbackToFileTransfer(id: id, title: title, author: author, text: text, wordCount: wordCount)
        }
    }

    private func fallbackToFileTransfer(id: UUID, title: String, author: String, text: String, wordCount: Int) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            WCSession.default.transferFile(tempURL, metadata: [
                "id": id.uuidString,
                "title": title,
                "author": author,
                "wordCount": wordCount
            ])
        } catch {
            DispatchQueue.main.async {
                self.sendState = .failed("Failed to prepare book")
                self.clearSendStateAfterDelay()
            }
        }
    }

    private func clearSendStateAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.sendState = .idle
        }
    }
    #endif

    // Bidirectional: sync reading position
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
        let title: String; let author: String; let text: String; var position: Int
    }

    func loadLibrary() {
        if let data = try? Data(contentsOf: Self.libraryURL),
           let lib = try? JSONDecoder().decode(WatchLibrary.self, from: data) {
            library = lib
            return
        }
        // Migrate from legacy single-book
        if let data = try? Data(contentsOf: Self.legacyBookURL),
           let legacy = try? JSONDecoder().decode(LegacyPersistedBook.self, from: data) {
            let book = WatchBook(
                id: UUID(), title: legacy.title, author: legacy.author, text: legacy.text,
                lastReadIndex: legacy.position, lastReadDate: nil,
                wordCount: legacy.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count,
                dateAdded: Date()
            )
            library = WatchLibrary(books: [book], currentBookId: book.id)
            persistLibrary()
            try? FileManager.default.removeItem(at: Self.legacyBookURL)
        }
    }

    func persistLibrary() {
        try? JSONEncoder().encode(library).write(to: Self.libraryURL)
    }
    #endif

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        print("[WatchSync] Activation completed: state=\(state.rawValue) error=\(String(describing: error))")
        #if os(iOS)
        print("[WatchSync] isPaired=\(session.isPaired) isWatchAppInstalled=\(session.isWatchAppInstalled) isReachable=\(session.isReachable)")
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.sendState = .failed(error.localizedDescription)
            } else {
                let title = fileTransfer.file.metadata?["title"] as? String ?? "Book"
                self.sendState = .sent(title)
            }
            self.clearSendStateAfterDelay()
        }
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            #if os(watchOS)
            if let bookIdStr = applicationContext["bookId"] as? String,
               let bookId = UUID(uuidString: bookIdStr),
               let index = applicationContext["wordIndex"] as? Int {
                self.library.updatePosition(bookId: bookId, index: index)
                self.persistLibrary()
            }
            #endif
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("[WatchSync] didReceiveMessage with keys: \(message.keys.sorted())")
        guard let title = message["title"] as? String,
              let author = message["author"] as? String,
              let text = message["text"] as? String else {
            replyHandler(["status": "error"])
            return
        }

        let bookId: UUID
        if let idStr = message["id"] as? String, let parsed = UUID(uuidString: idStr) {
            bookId = parsed
        } else {
            bookId = UUID()
        }
        let wordCount: Int
        if let wc = message["wordCount"] as? Int {
            wordCount = wc
        } else {
            wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }

        DispatchQueue.main.async {
            #if os(watchOS)
            self.isReceiving = true
            self.receivingTitle = title

            // Dedup check
            if self.library.books.contains(where: { $0.id == bookId }) {
                WKInterfaceDevice.current().play(.click)
                self.isReceiving = false
                self.receivingTitle = nil
            } else {
                let book = WatchBook(
                    id: bookId, title: title, author: author, text: text,
                    lastReadIndex: 0, lastReadDate: nil,
                    wordCount: wordCount, dateAdded: Date()
                )
                self.library.addBook(book)
                self.persistLibrary()
                WKInterfaceDevice.current().play(.success)
                self.isReceiving = false
                self.receivingTitle = nil
            }
            #endif
        }
        replyHandler(["status": "ok"])
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        print("[WatchSync] didReceive file with metadata: \(file.metadata ?? [:])")
        let metadata = file.metadata ?? [:]
        #if os(watchOS)
        DispatchQueue.main.async {
            self.isReceiving = true
            self.receivingTitle = metadata["title"] as? String
        }
        #endif
        guard let text = try? String(contentsOf: file.fileURL, encoding: .utf8) else {
            #if os(watchOS)
            DispatchQueue.main.async {
                self.isReceiving = false
                self.receivingTitle = nil
            }
            #endif
            return
        }

        let title = metadata["title"] as? String
        let author = metadata["author"] as? String

        let bookId: UUID
        if let idStr = metadata["id"] as? String, let parsed = UUID(uuidString: idStr) {
            bookId = parsed
        } else {
            bookId = UUID()
        }
        let wordCount: Int
        if let wc = metadata["wordCount"] as? Int {
            wordCount = wc
        } else {
            wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }

        DispatchQueue.main.async {
            #if os(watchOS)
            if self.library.books.contains(where: { $0.id == bookId }) {
                WKInterfaceDevice.current().play(.click)
            } else {
                let book = WatchBook(
                    id: bookId, title: title ?? "Untitled", author: author ?? "Unknown", text: text,
                    lastReadIndex: 0, lastReadDate: nil,
                    wordCount: wordCount, dateAdded: Date()
                )
                self.library.addBook(book)
                self.persistLibrary()
                WKInterfaceDevice.current().play(.success)
            }
            self.isReceiving = false
            self.receivingTitle = nil
            #endif
        }
    }
}
