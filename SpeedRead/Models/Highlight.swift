//  Highlight.swift
import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var startWordIndex: Int
    var endWordIndex: Int
    var highlightedText: String
    var createdAt: Date
    var book: Book?
    var note: String? = nil
    /// The last local change to what syncs (the note). Nil until one is made: `createdAt` stands.
    var modifiedAt: Date? = nil
    /// When the library server last agreed with this highlight. Nil: never sent.
    var syncedAt: Date? = nil
    /// The server's id for a highlight another reader made. Nil for one made here, whose id is
    /// `id`.
    var syncID: String? = nil
    /// The reader that made it, when not this app. Only this app's own rows can be changed on
    /// the server.
    var syncSource: String? = nil
    /// The device that made it, as the server names it. An edit sent from here keeps it, so the
    /// highlight stays credited to the device it came from.
    var syncOriginDevice: String? = nil

    init(startWordIndex: Int, endWordIndex: Int, highlightedText: String) {
        self.id = UUID()
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
        self.highlightedText = highlightedText
        self.createdAt = Date()
    }

    var annotationID: String { syncID ?? id.uuidString }
    var isEditableOnServer: Bool { syncSource == nil || syncSource == KOSyncAnnotationPush.source }
    var needsPush: Bool {
        guard isEditableOnServer else { return false }
        guard let syncedAt else { return true }
        return (modifiedAt ?? createdAt) > syncedAt
    }

    /// A blank note is no note.
    func setNote(_ text: String?, at date: Date = Date()) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = trimmed?.isEmpty == false ? trimmed : nil
        guard new != note else { return }
        note = new
        modifiedAt = date
    }

    var wordSpan: Int {
        endWordIndex - startWordIndex + 1
    }

    static func captureText(from words: [String], start: Int, end: Int) -> String {
        guard start >= 0, end < words.count, start <= end else { return "" }
        return words[start...end].joined(separator: " ")
    }
}
