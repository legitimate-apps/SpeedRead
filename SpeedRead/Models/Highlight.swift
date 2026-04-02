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

    init(startWordIndex: Int, endWordIndex: Int, highlightedText: String) {
        self.id = UUID()
        self.startWordIndex = startWordIndex
        self.endWordIndex = endWordIndex
        self.highlightedText = highlightedText
        self.createdAt = Date()
    }

    var wordSpan: Int {
        endWordIndex - startWordIndex + 1
    }

    static func captureText(from words: [String], start: Int, end: Int) -> String {
        guard start >= 0, end < words.count, start <= end else { return "" }
        return words[start...end].joined(separator: " ")
    }
}
