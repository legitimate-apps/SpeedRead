import Foundation
import WatchConnectivity

final class WatchFileFixture: WCSessionFile {
    private let fixtureURL: URL
    private let fixtureMetadata: [String: Any]?

    init(url: URL, metadata: [String: Any]?) {
        fixtureURL = url
        fixtureMetadata = metadata
        super.init()
    }

    override var fileURL: URL { fixtureURL }
    override var metadata: [String: Any]? { fixtureMetadata }
}

final class WatchFileTransferFixture: WCSessionFileTransfer {
    private let fixtureFile: WCSessionFile

    init(metadata: [String: Any]?) {
        fixtureFile = WatchFileFixture(url: URL(fileURLWithPath: "/unused-transfer.txt"), metadata: metadata)
        super.init()
    }

    override var file: WCSessionFile { fixtureFile }
}
