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

    init(wordIndex: Int, previewText: String) {
        self.id = UUID()
        self.wordIndex = wordIndex
        self.previewText = previewText
        self.createdAt = Date()
    }

    static func previewText(from words: [String], at index: Int, windowSize: Int = 5) -> String {
        guard !words.isEmpty else { return "" }
        let half = windowSize / 2
        let start = max(0, index - half)
        let end = min(words.count, start + windowSize)
        return words[start..<end].joined(separator: " ")
    }
}
