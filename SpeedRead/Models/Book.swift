//  Book.swift
import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var extractedText: String
    var sourceFileName: String
    var dateAdded: Date
    var lastReadWordIndex: Int
    var lastReadDate: Date?

    init(
        title: String,
        author: String,
        extractedText: String,
        sourceFileName: String
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.extractedText = extractedText
        self.sourceFileName = sourceFileName
        self.dateAdded = Date()
        self.lastReadWordIndex = 0
        self.lastReadDate = nil
    }

    var words: [String] {
        extractedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    var progress: Double {
        let totalWords = words.count
        guard totalWords > 0 else { return 0.0 }
        return Double(lastReadWordIndex) / Double(totalWords)
    }
}
