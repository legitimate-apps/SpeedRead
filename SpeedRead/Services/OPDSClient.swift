//  OPDSClient.swift
import Foundation

nonisolated enum OPDSError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureSchemeBlocked
    case httpError(status: Int)
    case parseError
    case networkError(String)
    case cancelled
    case deviceRemoved(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "This server address isn't a web address SpeedRead can use."
        case .insecureSchemeBlocked:
            return "This server uses plain HTTP, which is off for it. Switch to HTTPS, or allow plain HTTP in the server's settings."
        case .httpError(let status):
            switch status {
            case 401: return "The server didn't accept this username and password. Check them in the server's settings."
            case 403: return "The server refused this account. It may not be allowed to use the catalog or to download."
            case 404: return "The server has nothing at this address. Check the catalog address in the server's settings."
            case 429: return "The server has had too many attempts from this account. Wait a minute, then try again."
            case 500...599: return "The server had a problem (error \(status)). Try again later."
            default: return "The server couldn't answer this request (error \(status))."
            }
        case .parseError: return "The server's answer isn't a catalog SpeedRead can read."
        case .networkError(let reason): return "SpeedRead couldn't reach the server. \(Self.sentence(reason))"
        case .cancelled: return "The request was cancelled."
        case .deviceRemoved(let message):
            let said = message.map(Self.sentence) ?? "This device was removed from your library account, so it no longer syncs."
            return "\(said) SpeedRead has stopped sending your place to this server."
        }
    }

    /// A transport failure in the reader's words. The system's own text for these is often
    /// "The operation couldn't be completed. (NSURLErrorDomain error -1009.)".
    static func transport(_ error: Error) -> OPDSError {
        guard let url = error as? URLError else { return .networkError(error.localizedDescription) }
        switch url.code {
        case .cancelled: return .cancelled
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .networkError("This device is offline.")
        case .timedOut: return .networkError("The server took too long to answer.")
        case .cannotFindHost, .dnsLookupFailed: return .networkError("There is no server at this address.")
        case .cannotConnectToHost: return .networkError("The server isn't answering.")
        case .networkConnectionLost: return .networkError("The connection dropped.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return .networkError("A secure connection to the server couldn't be made.")
        default: return .networkError(url.localizedDescription)
        }
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}

/// Value snapshot taken on the model owner's executor before crossing to the network actor.
/// The SwiftData object stays with its context while a request is in flight.
nonisolated struct OPDSRequestConfiguration: Sendable {
    let baseURL: URL?
    let username: String
    let keychainTag: String
    let allowInsecureHTTP: Bool

    init(_ server: OPDSServer) {
        baseURL = server.baseURL
        username = server.username
        keychainTag = server.keychainTag
        allowInsecureHTTP = server.allowInsecureHTTP
    }

    var requiresAuth: Bool { !username.isEmpty }
}

/// Network access for OPDS catalogs. Builds requests with HTTP Basic Auth
/// when the server has a username, enforces the per-server insecure-HTTP gate,
/// and routes raw bytes / parsed feeds back to the caller.
actor OPDSClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeed(url: URL, on server: OPDSRequestConfiguration) async throws -> OPDSFeed {
        try validateScheme(url: url, server: server)
        let request = try makeRequest(url: url, server: server, accept: "application/atom+xml")
        let (data, response) = try await perform(request)
        try ensure2xx(response)
        let parser = OPDSAtomParser(baseURL: server.baseURL ?? url)
        do {
            return try parser.parse(data: data)
        } catch {
            throw OPDSError.parseError
        }
    }

    func download(from url: URL, on server: OPDSRequestConfiguration) async throws -> OPDSDownload {
        try validateScheme(url: url, server: server)
        let request = try makeRequest(url: url, server: server, accept: nil)
        let (data, response) = try await perform(request)
        try ensure2xx(response)
        let filename = Self.deriveFilename(response: response, fallbackURL: url)
        return OPDSDownload(data: data, filename: filename)
    }

    /// A book, written to disk as it arrives instead of held in memory. The file is the caller's,
    /// to import and then `remove()`; nothing is left behind when the download fails.
    func downloadFile(from url: URL, on server: OPDSRequestConfiguration) async throws -> OPDSDownloadedFile {
        try validateScheme(url: url, server: server)
        let request = try makeRequest(url: url, server: server, accept: nil)
        let temporary: URL, response: URLResponse
        do {
            (temporary, response) = try await session.download(for: request)
        } catch {
            throw OPDSError.transport(error)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try ensure2xx(response)
        let filename = Self.deriveFilename(response: response, fallbackURL: url)
        let location = try OPDSDownloadedFile.newLocation()
        do {
            try FileManager.default.moveItem(at: temporary, to: location)
        } catch {
            throw OPDSError.networkError("The downloaded file couldn't be saved.")
        }
        return OPDSDownloadedFile(location: location, filename: filename)
    }

    func testConnection(_ server: OPDSRequestConfiguration) async throws -> Bool {
        guard let base = server.baseURL else { throw OPDSError.invalidURL }
        let feed = try await fetchFeed(url: base, on: server)
        return !feed.entries.isEmpty || !feed.navigationLinks.isEmpty || !feed.title.isEmpty
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw OPDSError.transport(error)
        }
    }

    private func validateScheme(url: URL, server: OPDSRequestConfiguration) throws {
        guard let scheme = url.scheme?.lowercased() else { throw OPDSError.invalidURL }
        if scheme == "http" && !server.allowInsecureHTTP {
            throw OPDSError.insecureSchemeBlocked
        }
        if scheme != "http" && scheme != "https" {
            throw OPDSError.invalidURL
        }
    }

    private func ensure2xx(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OPDSError.networkError("Its answer wasn't a web response.")
        }
        if !(200...299).contains(http.statusCode) {
            throw OPDSError.httpError(status: http.statusCode)
        }
    }

    private func makeRequest(url: URL, server: OPDSRequestConfiguration, accept: String?) throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
        request.httpMethod = "GET"
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        request.setValue("SpeedRead/1.0 OPDS-Client", forHTTPHeaderField: "User-Agent")
        if server.requiresAuth {
            let password = KeychainStore.password(for: server.keychainTag) ?? ""
            let combo = "\(server.username):\(password)"
            guard let data = combo.data(using: .utf8) else { throw OPDSError.invalidURL }
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Picks the best filename from a Content-Disposition header, falling back
    /// to the URL last component, then to a hash-based name when both are empty.
    static func deriveFilename(response: URLResponse, fallbackURL: URL) -> String {
        if let http = response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let parsed = parseContentDispositionFilename(disposition), !parsed.isEmpty {
                return parsed
            }
        }
        let last = fallbackURL.lastPathComponent
        if !last.isEmpty && last != "/" && last.contains(".") {
            return last
        }
        return "download.bin"
    }

    private static func parseContentDispositionFilename(_ header: String) -> String? {
        let lower = header.lowercased()
        if let starRange = lower.range(of: "filename*=") {
            let value = header[starRange.upperBound...]
            if let semi = value.firstIndex(of: ";") {
                return decodeRFC5987(String(value[..<semi]).trimmingCharacters(in: .whitespaces))
            }
            return decodeRFC5987(String(value).trimmingCharacters(in: .whitespaces))
        }
        if let plainRange = lower.range(of: "filename=") {
            let value = header[plainRange.upperBound...]
            var s: String
            if let semi = value.firstIndex(of: ";") {
                s = String(value[..<semi])
            } else {
                s = String(value)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
                s.removeFirst()
                s.removeLast()
            }
            return s.isEmpty ? nil : s
        }
        return nil
    }

    /// `charset'language'percent-encoded`. RFC 5987 requires UTF-8 and ISO-8859-1.
    private static func decodeRFC5987(_ value: String) -> String? {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return value.removingPercentEncoding ?? value }
        let raw = String(parts[2])
        let encoding: String.Encoding = parts[0].lowercased() == "iso-8859-1" ? .isoLatin1 : .utf8
        return percentDecoded(raw, encoding: encoding) ?? raw
    }

    private static func percentDecoded(_ raw: String, encoding: String.Encoding) -> String? {
        let utf8 = Array(raw.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < utf8.count {
            if utf8[index] == UInt8(ascii: "%"), index + 2 < utf8.count,
               let value = UInt8(String(decoding: utf8[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                bytes.append(value)
                index += 3
            } else {
                bytes.append(utf8[index])
                index += 1
            }
        }
        return String(bytes: bytes, encoding: encoding)
    }
}

/// A downloaded book on disk, named by the server's filename but stored under a name of our own.
nonisolated struct OPDSDownloadedFile: Equatable, Sendable {
    let location: URL
    let filename: String

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OPDSDownloads", isDirectory: true)
    }

    static func newLocation() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString)
    }

    static func directoryContents() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: location)
    }
}

nonisolated struct OPDSDownload: Equatable, Sendable {
    let data: Data
    let filename: String
}
