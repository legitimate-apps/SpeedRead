import Combine
import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    @Published var lastReceivedBookTitle: String?
    @Published var lastReceivedBookText: String?
    @Published var lastReceivedBookAuthor: String?
    @Published var lastReceivedPosition: Int = 0

    #if os(watchOS)
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
        loadPersistedBook()
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
    func sendBook(title: String, author: String, text: String) {
        guard WCSession.default.activationState == .activated else {
            sendState = .failed("Watch not connected")
            clearSendStateAfterDelay()
            return
        }

        sendState = .sending(title)
        let message: [String: Any] = ["title": title, "author": author, "text": text]

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
                self.fallbackToFileTransfer(title: title, author: author, text: text)
            })
        } else {
            print("[WatchSync] Watch not reachable, using transferFile fallback...")
            fallbackToFileTransfer(title: title, author: author, text: text)
        }
    }

    private func fallbackToFileTransfer(title: String, author: String, text: String) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            WCSession.default.transferFile(tempURL, metadata: ["title": title, "author": author])
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
    func syncReadingPosition(bookTitle: String, wordIndex: Int) {
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext([
            "bookTitle": bookTitle,
            "wordIndex": wordIndex,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    #if os(watchOS)
    private struct PersistedBook: Codable {
        let title: String
        let author: String
        let text: String
        var position: Int
    }

    private static var persistURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watchbook.json")
    }

    func loadPersistedBook() {
        guard let data = try? Data(contentsOf: Self.persistURL),
              let book = try? JSONDecoder().decode(PersistedBook.self, from: data) else { return }
        lastReceivedBookTitle = book.title
        lastReceivedBookAuthor = book.author
        lastReceivedBookText = book.text
        lastReceivedPosition = book.position
    }

    private func persistBook() {
        guard let title = lastReceivedBookTitle,
              let author = lastReceivedBookAuthor,
              let text = lastReceivedBookText else { return }
        let book = PersistedBook(title: title, author: author, text: text, position: lastReceivedPosition)
        try? JSONEncoder().encode(book).write(to: Self.persistURL)
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
            if let title = applicationContext["bookTitle"] as? String {
                self.lastReceivedBookTitle = title
            }
            if let index = applicationContext["wordIndex"] as? Int {
                self.lastReceivedPosition = index
            }
            #if os(watchOS)
            self.persistBook()
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
        DispatchQueue.main.async {
            #if os(watchOS)
            self.isReceiving = true
            self.receivingTitle = title
            #endif
            self.lastReceivedBookTitle = title
            self.lastReceivedBookAuthor = author
            self.lastReceivedBookText = text
            self.lastReceivedPosition = 0
            #if os(watchOS)
            self.persistBook()
            WKInterfaceDevice.current().play(.success)
            self.isReceiving = false
            self.receivingTitle = nil
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
        if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
            DispatchQueue.main.async {
                self.lastReceivedBookTitle = metadata["title"] as? String
                self.lastReceivedBookAuthor = metadata["author"] as? String
                self.lastReceivedBookText = text
                self.lastReceivedPosition = 0
                #if os(watchOS)
                self.persistBook()
                WKInterfaceDevice.current().play(.success)
                self.isReceiving = false
                self.receivingTitle = nil
                #endif
            }
        }
    }
}
