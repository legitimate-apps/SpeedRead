//  OPDSServer.swift
import Foundation
import SwiftData

@Model
final class OPDSServer {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURLString: String
    var username: String
    var keychainTag: String
    var allowInsecureHTTP: Bool
    var lastUsedAt: Date?
    var sortIndex: Int

    init(
        name: String,
        baseURL: URL,
        username: String,
        allowInsecureHTTP: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.baseURLString = baseURL.absoluteString
        self.username = username
        self.keychainTag = UUID().uuidString
        self.allowInsecureHTTP = allowInsecureHTTP
        self.lastUsedAt = nil
        self.sortIndex = sortIndex
    }

    var baseURL: URL? {
        URL(string: baseURLString)
    }

    var requiresAuth: Bool {
        !username.isEmpty
    }
}
