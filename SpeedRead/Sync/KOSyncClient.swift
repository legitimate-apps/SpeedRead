import Foundation

/// What a library server can do with reading positions, learned from `GET /kosync/users/auth`.
nonisolated enum KOSyncServerSupport: Equatable, Sendable {
    /// Accepts a percentage with a text anchor and resolves it for the other readers.
    case anchorPositions
    /// A stock KOSync server, an older server, or none at all. A stock server would trust any
    /// `progress` we sent as an xpointer and mis-seek KOReader, so SpeedRead never pushes to one.
    case unsupported
}

/// A position pushed for one book: a percentage plus the words at it, never an xpointer.
nonisolated struct KOSyncPush: Encodable, Equatable, Sendable {
    let document: String
    let percentage: Double
    let device: String
    let deviceID: String
    let anchor: ReadingAnchor?
    let positionKind = "percentage"

    enum CodingKeys: String, CodingKey {
        case document, percentage, device, anchor
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

    static func support(fromAuthBody data: Data) -> KOSyncServerSupport {
        capabilities(fromAuthBody: data).contains("anchor") ? .anchorPositions : .unsupported
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
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Every capability the server names in its auth answer; empty for a stock or older server.
    func capabilities(of server: OPDSRequestConfiguration) async throws -> Set<String> {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { return [] }
        let (data, status) = try await send(KOSyncWire.authURL(base: base), method: "GET", server: server)
        // A stock server answers Basic with 401 (it wants its own x-auth headers); a server
        // without KOSync answers 404. Neither is a failure: it is a server we do not write to.
        guard (200...299).contains(status) else {
            if [401, 403, 404, 405].contains(status) { return [] }
            throw OPDSError.httpError(status: status)
        }
        return KOSyncWire.capabilities(fromAuthBody: data)
    }

    func support(of server: OPDSRequestConfiguration) async throws -> KOSyncServerSupport {
        try await capabilities(of: server).contains("anchor") ? .anchorPositions : .unsupported
    }

    func push(_ position: KOSyncPush, to server: OPDSRequestConfiguration) async throws {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { throw OPDSError.invalidURL }
        var request = try request(KOSyncWire.pushURL(base: base), method: "PUT", server: server)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try KOSyncWire.encode(position)
        let (_, status) = try await perform(request)
        guard (200...299).contains(status) else { throw OPDSError.httpError(status: status) }
    }

    func position(of document: String, on server: OPDSRequestConfiguration) async throws -> KOSyncRemotePosition? {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL),
              let url = KOSyncWire.fetchURL(base: base, document: document) else { throw OPDSError.invalidURL }
        let (data, status) = try await perform(request(url, method: "GET", server: server))
        guard (200...299).contains(status) else { throw OPDSError.httpError(status: status) }
        do {
            return try KOSyncWire.decodePosition(data)
        } catch {
            throw OPDSError.parseError
        }
    }

    func send(_ url: URL, method: String, server: OPDSRequestConfiguration, body: Data? = nil) async throws -> (Data, Int) {
        var request = try request(url, method: method, server: server)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await perform(request)
    }

    private func request(_ url: URL, method: String, server: OPDSRequestConfiguration) throws -> URLRequest {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw OPDSError.invalidURL
        }
        if scheme == "http" && !server.allowInsecureHTTP { throw OPDSError.insecureSchemeBlocked }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue(KOSyncWire.accept, forHTTPHeaderField: "Accept")
        request.setValue("SpeedRead/1.0 KOSync-Client", forHTTPHeaderField: "User-Agent")
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
        } catch let error as URLError where error.code == .cancelled {
            throw OPDSError.cancelled
        } catch {
            throw OPDSError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw OPDSError.networkError("Non-HTTP response") }
        return (data, http.statusCode)
    }
}
