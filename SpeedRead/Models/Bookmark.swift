//  Bookmark.swift
import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID
    var wordIndex: Int
    var previewText: String
    var createdAt: Date
    var book: Book?
    /// When the library server last agreed with this bookmark. Nil: never sent.
    var syncedAt: Date? = nil
    /// The server's id for a bookmark another reader made. Nil for one made here, whose id is `id`.
    var syncID: String? = nil
    /// The reader that made it, when not this app.
    var syncSource: String? = nil

    init(wordIndex: Int, previewText: String) {
        self.id = UUID()
        self.wordIndex = wordIndex
        self.previewText = previewText
        self.createdAt = Date()
    }

    var annotationID: String { syncID ?? id.uuidString }
    var isEditableOnServer: Bool { syncSource == nil || syncSource == KOSyncAnnotationPush.source }
    var needsPush: Bool { isEditableOnServer && syncedAt == nil }

    static func previewText(from words: [String], at index: Int, windowSize: Int = 5) -> String {
        guard !words.isEmpty else { return "" }
        let half = windowSize / 2
        let start = max(0, index - half)
        let end = min(words.count, start + windowSize)
        return words[start..<end].joined(separator: " ")
    }
}
