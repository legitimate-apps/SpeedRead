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
    /// The reader that made it, for one pulled from the server. Nil: made here.
    var syncSource: String? = nil
    /// The device that made it, as the server names it. With `syncSource`, it decides who may
    /// change it on the server: `AnnotationSyncLogic.isOwned`.
    var syncOriginDevice: String? = nil

    init(startWordIndex: Int, endWordIndex: Int, highlightedText: String) {
        self.id = UUID()
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
        self.highlightedText = highlightedText
        self.createdAt = Date()
    }

    var annotationID: String { syncID ?? id.uuidString }
    func isOwned(by deviceID: String) -> Bool {
        AnnotationSyncLogic.isOwned(source: syncSource, originDevice: syncOriginDevice, deviceID: deviceID)
    }

    /// A change made here that the server has not taken yet, on a row this device may change.
    func needsPush(by deviceID: String) -> Bool {
        guard isOwned(by: deviceID) else { return false }
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
