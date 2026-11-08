import Foundation

/// What a library server can do with reading positions, learned from `GET /kosync/users/auth`.
nonisolated enum KOSyncServerSupport: Equatable, Sendable {
    /// Accepts a percentage with a text anchor and resolves it for the other readers.
    case anchorPositions
    /// A stock KOSync server, an older server, or none at all. A stock server would trust any
    /// `progress` we sent as an xpointer and mis-seek KOReader, so SpeedRead never pushes to one.
    case unsupported
    /// The server has sync but refused these credentials (401 or 403 from CWNG): nothing is
    /// written, and the reader is told it is the username and password.
    case credentialsRefused
}

/// Whether a server shares this device's place with the account's other readers, from the auth
/// answer. CWNG gates places per device (`share_place_gates`); a device starts unshared.
nonisolated enum KOSyncPlaceSharing: Equatable, Sendable {
    /// The server does not gate places by device: every place is shared.
    case notGated
    case shared
    /// Gated, and this device's place is not known to be shared.
    case notShared
}

/// What the auth probe learned.
nonisolated struct KOSyncServerStatus: Equatable, Sendable {
    let support: KOSyncServerSupport
    let placeSharing: KOSyncPlaceSharing
}

/// How this device names itself to the server: the `device_id` its pushes already carry, sent as
/// `X-CWNG-Device-ID` so CWNG can tell its readers apart.
nonisolated struct KOSyncDevice: Equatable, Sendable {
    let id: String
    let name: String
}

/// A position pushed for one book: a percentage plus the words at it, never an xpointer.
nonisolated struct KOSyncPush: Encodable, Equatable, Sendable {
    let document: String
    let percentage: Double
    let device: String
    let deviceID: String
    let anchor: ReadingAnchor?
    /// When the reader was at this place, epoch seconds (CWNG's `client_clock`).
    var timestamp: Int? = nil
    let positionKind = "percentage"

    enum CodingKeys: String, CodingKey {
        case document, percentage, device, anchor, timestamp
        case deviceID = "device_id"
        case positionKind = "position_kind"
    }
}

/// The winning position the server holds for a book, from whichever reader set it.
nonisolated struct KOSyncRemotePosition: Equatable, Sendable {
    /// 0–1.
    let percentage: Double
    let anchor: ReadingAnchor?
    let device: String?
    let deviceID: String?
    /// When the server received it, not when the reading happened.
    let timestamp: Date?
}

/// Wire shapes and URLs. Pure, so every byte the client sends is testable without a session.
nonisolated enum KOSyncWire {
    static let accept = "application/vnd.koreader.v1+json"

    /// The KOSync base for a server whose OPDS feed lives at `…/opds`: `…/kosync`. Any other
    /// layout has no known sync endpoint.
    static func kosyncBase(fromOPDS opds: URL?) -> URL? {
        guard let opds, var components = URLComponents(url: opds, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.last?.lowercased() == "opds" else { return nil }
        path.removeLast()
        components.path = "/" + (path + ["kosync"]).joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func authURL(base: URL) -> URL {
        base.appendingPathComponent("users").appendingPathComponent("auth")
    }

    static func pushURL(base: URL) -> URL {
        base.appendingPathComponent("syncs").appendingPathComponent("progress")
    }

    static func fetchURL(base: URL, document: String) -> URL? {
        var components = URLComponents(
            url: base.appendingPathComponent("syncs").appendingPathComponent("progress")
                .appendingPathComponent(document),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "position_kinds", value: "locator,percentage,anchor")]
        return components?.url
    }

    static func capabilities(fromAuthBody data: Data) -> Set<String> {
        struct Auth: Decodable { let capabilities: [String]? }
        return Set((try? JSONDecoder().decode(Auth.self, from: data))?.capabilities ?? [])
    }

    /// `share_place_gates` says the server keeps each device's place private unless it is shared;
    /// `share_place`, when the server sends it, says whether this device's is. Absent means not known
    /// to be shared, so the reader is still told how.
    static func placeSharing(fromAuthBody data: Data) -> KOSyncPlaceSharing {
        struct Auth: Decodable {
            let share_place_gates: Bool?
            let share_place: Bool?
        }
        guard let auth = try? JSONDecoder().decode(Auth.self, from: data), auth.share_place_gates == true else {
            return .notGated
        }
        return auth.share_place == true ? .shared : .notShared
    }

    /// CWNG's `client_clock` throws away a time before 2000 or more than five minutes past its own
    /// receipt, and then judges the push by when it arrived. A clock ahead of `now` is sent as `now`.
    static func clientClock(_ date: Date?, now: Date) -> Int? {
        guard let date else { return nil }
        let seconds = min(date, now).timeIntervalSince1970
        guard seconds.isFinite, seconds >= 946_684_800 else { return nil }
        return Int(seconds.rounded(.down))
    }

    static func support(fromAuthBody data: Data) -> KOSyncServerSupport {
        capabilities(fromAuthBody: data).contains("anchor") ? .anchorPositions : .unsupported
    }

    /// CWNG's answer to a push from a device removed from the account: 409
    /// `{"error":"device_inactive","message":"…"}`. The outer optional is whether it is that
    /// answer at all; the inner, whether it carried a message.
    static func removedDeviceMessage(_ data: Data) -> String?? {
        struct Body: Decodable { let error: String?; let message: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), body.error == "device_inactive" else {
            return nil
        }
        return .some(body.message?.isEmpty == false ? body.message : nil)
    }

    static func encode(_ push: KOSyncPush) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(push)
    }

    /// `{}` — no position stored for this document — decodes to nil, as does a body with no
    /// usable percentage.
    static func decodePosition(_ data: Data) throws -> KOSyncRemotePosition? {
        struct Body: Decodable {
            let percentage: Double?
            let anchor: ReadingAnchor?
            let device: String?
            let device_id: String?
            let timestamp: Double?
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        guard let raw = body.percentage, raw.isFinite, raw >= 0 else { return nil }
        // The protocol is 0–1. A value above 1 can only be a 0–100 percentage.
        let percentage = min(raw > 1 ? raw / 100 : raw, 1)
        return KOSyncRemotePosition(
            percentage: percentage,
            anchor: body.anchor,
            device: body.device,
            deviceID: body.device_id,
            timestamp: body.timestamp.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

/// KOSync over the library server's own OPDS credentials (HTTP Basic). Shares `OPDSError` and
/// the insecure-HTTP gate with `OPDSClient`, so a server behaves the same in both.
actor KOSyncClient {
    nonisolated let session: URLSession

    nonisolated let device: KOSyncDevice?

    init(session: URLSession = .shared, device: KOSyncDevice? = nil) {
        self.session = session
        self.device = device
    }

    /// This client, naming itself as `device` on its position calls.
    nonisolated func identified(as device: KOSyncDevice) -> KOSyncClient {
        KOSyncClient(session: session, device: device)
    }

    private enum Probe {
        case answered(Data)
        case refused
        case absent
    }

    private func probe(_ server: OPDSRequestConfiguration) async throws -> Probe {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { return .absent }
        let (data, status) = try await perform(request(KOSyncWire.authURL(base: base), method: "GET", server: server,
                                                        identified: true))
        switch status {
        case 200...299: return .answered(data)
        // CWNG answers a wrong password with 401 (OBSERVED, v4.1.63). A stock server does too,
        // since it wants its own x-auth headers, so this is never written to either way.
        case 401, 403: return .refused
        // No KOSync at all.
        case 404, 405: return .absent
        default: throw OPDSError.httpError(status: status)
        }
    }

    /// Every capability the server names in its auth answer; empty for a stock or older server,
    /// or one that refused the credentials.
    func capabilities(of server: OPDSRequestConfiguration) async throws -> Set<String> {
        guard case .answered(let data) = try await probe(server) else { return [] }
        return KOSyncWire.capabilities(fromAuthBody: data)
    }

    func status(of server: OPDSRequestConfiguration) async throws -> KOSyncServerStatus {
        switch try await probe(server) {
        case .answered(let data):
            KOSyncServerStatus(support: KOSyncWire.support(fromAuthBody: data),
                               placeSharing: KOSyncWire.placeSharing(fromAuthBody: data))
        case .refused: KOSyncServerStatus(support: .credentialsRefused, placeSharing: .notGated)
        case .absent: KOSyncServerStatus(support: .unsupported, placeSharing: .notGated)
        }
    }

    func support(of server: OPDSRequestConfiguration) async throws -> KOSyncServerSupport {
        try await status(of: server).support
    }

    func push(_ position: KOSyncPush, to server: OPDSRequestConfiguration) async throws {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { throw OPDSError.invalidURL }
        var request = try request(KOSyncWire.pushURL(base: base), method: "PUT", server: server, identified: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try KOSyncWire.encode(position)
        let (data, status) = try await perform(request)
        guard (200...299).contains(status) else {
            if status == 409, let message = KOSyncWire.removedDeviceMessage(data) { throw OPDSError.deviceRemoved(message) }
            throw OPDSError.httpError(status: status)
        }
    }

    func position(of document: String, on server: OPDSRequestConfiguration) async throws -> KOSyncRemotePosition? {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL),
              let url = KOSyncWire.fetchURL(base: base, document: document) else { throw OPDSError.invalidURL }
        let (data, status) = try await perform(request(url, method: "GET", server: server, identified: true))
        guard (200...299).contains(status) else { throw OPDSError.httpError(status: status) }
        do {
            return try KOSyncWire.decodePosition(data)
        } catch {
            throw OPDSError.parseError
        }
    }

    /// Annotation calls. These never name the device: CWNG serves an annotation GET that names one
    /// only that device's own highlights (its share-my-place spec, §17).
    func send(_ url: URL, method: String, server: OPDSRequestConfiguration, body: Data? = nil) async throws -> (Data, Int) {
        var request = try request(url, method: method, server: server)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await perform(request)
    }

    private func request(_ url: URL, method: String, server: OPDSRequestConfiguration,
                         identified: Bool = false) throws -> URLRequest {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw OPDSError.invalidURL
        }
        if scheme == "http" && !server.allowInsecureHTTP { throw OPDSError.insecureSchemeBlocked }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue(KOSyncWire.accept, forHTTPHeaderField: "Accept")
        request.setValue("SpeedRead/1.0 KOSync-Client", forHTTPHeaderField: "User-Agent")
        if identified, let device {
            request.setValue(device.id, forHTTPHeaderField: "X-CWNG-Device-ID")
            request.setValue(device.name, forHTTPHeaderField: "X-CWNG-Device-Name")
        }
        if server.requiresAuth {
            let password = KeychainStore.password(for: server.keychainTag) ?? ""
            let credentials = Data("\(server.username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OPDSError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OPDSError.networkError("Non-HTTP response") }
        return (data, http.statusCode)
    }
}
