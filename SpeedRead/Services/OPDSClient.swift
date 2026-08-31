//  OPDSClient.swift
import Foundation

nonisolated enum OPDSError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureSchemeBlocked
    case httpError(status: Int)
    case parseError
    case networkError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server URL is not valid."
        case .insecureSchemeBlocked:
            return "Plain HTTP is disabled for this server. Switch to HTTPS or enable insecure HTTP in Server settings."
        case .httpError(let status):
            switch status {
            case 401: return "Authentication failed (401). Check the username and password."
            case 403: return "Access denied (403). The user account may lack OPDS permission."
            case 404: return "Server returned 404. Check the OPDS base URL."
            case 500...599: return "Server error (\(status)). Try again later."
            default: return "HTTP error \(status)."
            }
        case .parseError: return "The server returned a response that could not be parsed as OPDS."
        case .networkError(let m): return "Network error: \(m)"
        case .cancelled: return "Request was cancelled."
        }
    }
}

/// Network access for OPDS catalogs. Builds requests with HTTP Basic Auth
/// when the server has a username, enforces the per-server insecure-HTTP gate,
/// and routes raw bytes / parsed feeds back to the caller.
actor OPDSClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeed(url: URL, on server: OPDSServer) async throws -> OPDSFeed {
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

    func download(from url: URL, on server: OPDSServer) async throws -> OPDSDownload {
        try validateScheme(url: url, server: server)
        let request = try makeRequest(url: url, server: server, accept: nil)
        let (data, response) = try await perform(request)
        try ensure2xx(response)
        let filename = Self.deriveFilename(response: response, fallbackURL: url)
        return OPDSDownload(data: data, filename: filename)
    }

    func testConnection(_ server: OPDSServer) async throws -> Bool {
        guard let base = server.baseURL else { throw OPDSError.invalidURL }
        let feed = try await fetchFeed(url: base, on: server)
        return !feed.entries.isEmpty || !feed.navigationLinks.isEmpty || !feed.title.isEmpty
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw OPDSError.cancelled
        } catch {
            throw OPDSError.networkError(error.localizedDescription)
        }
    }

    private func validateScheme(url: URL, server: OPDSServer) throws {
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
            throw OPDSError.networkError("Non-HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            throw OPDSError.httpError(status: http.statusCode)
        }
    }

    private func makeRequest(url: URL, server: OPDSServer, accept: String?) throws -> URLRequest {
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

    private static func decodeRFC5987(_ value: String) -> String? {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        let raw = parts.count == 3 ? String(parts[2]) : value
        return raw.removingPercentEncoding ?? raw
    }
}

nonisolated struct OPDSDownload: Equatable, Sendable {
    let data: Data
    let filename: String
}
