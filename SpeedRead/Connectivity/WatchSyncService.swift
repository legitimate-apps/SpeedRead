import Combine
import Foundation
import WatchConnectivity

final class WatchSyncService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    @Published var lastReceivedBookTitle: String?
    @Published var lastReceivedBookText: String?
    @Published var lastReceivedBookAuthor: String?
    @Published var lastReceivedPosition: Int = 0

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
        guard WCSession.isSupported() else { return }
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
        guard WCSession.default.isReachable else {
            sendState = .failed("Watch not reachable")
            clearSendStateAfterDelay()
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            WCSession.default.transferFile(tempURL, metadata: ["title": title, "author": author])
            sendState = .sending(title)
        } catch {
            sendState = .failed("Failed to prepare book")
            clearSendStateAfterDelay()
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

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

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
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        if let text = try? String(contentsOf: file.fileURL, encoding: .utf8) {
            DispatchQueue.main.async {
                self.lastReceivedBookTitle = metadata["title"] as? String
                self.lastReceivedBookAuthor = metadata["author"] as? String
                self.lastReceivedBookText = text
            }
        }
    }
}
