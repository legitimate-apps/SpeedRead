//  TextFileExtractor.swift
import Foundation

struct TextFileExtractor: TextExtractor {
    func extractText(from data: Data) throws -> ExtractionResult {
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let latin = String(data: data, encoding: .isoLatin1) {
            text = latin
        } else if let mac = String(data: data, encoding: .macOSRoman) {
            text = mac
        } else {
            throw ExtractionError.invalidData
        }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            throw ExtractionError.parsingFailed("File is empty")
        }

        let (title, body) = Self.detectTitle(in: normalized)
        return ExtractionResult(text: body, title: title, author: nil)
    }

    /// Detects a likely title from the first non-empty line of a plain-text file.
    /// Project Gutenberg-style "Title: X" headers are always trusted. Otherwise
    /// we conservatively accept the first short line, but reject patterns that
    /// commonly false-positive: ALL CAPS lines (chapter headings), lines that
    /// start with "CHAPTER" / "PROLOGUE" / "PART", lines that are mostly
    /// punctuation, and lines without any letters.
    static func detectTitle(in text: String) -> (title: String?, body: String) {
        let lines = text.split(separator: "\n", maxSplits: 8, omittingEmptySubsequences: false)
        guard let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return (nil, text)
        }

        let trimmed = firstNonEmpty.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("title:") {
            let title = trimmed.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
            return (title.isEmpty ? nil : title, text)
        }

        guard isPlausibleTitle(trimmed) else {
            return (nil, text)
        }
        return (trimmed, text)
    }

    private static func isPlausibleTitle(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= 80 else { return false }
        if line.contains(".") { return false }
        if line.split(separator: " ").count > 12 { return false }

        let letters = line.filter { $0.isLetter }
        guard letters.count >= 2 else { return false }

        // Reject ALL-CAPS lines (CHAPTER ONE, PART I, etc.). Accept titles that
        // happen to contain initialisms by allowing some lowercase letters.
        let lowercaseLetters = letters.filter { $0.isLowercase }
        if lowercaseLetters.isEmpty { return false }

        let blockedPrefixes = ["chapter ", "prologue", "epilogue", "part ", "section ", "preface", "introduction", "contents", "foreword"]
        let lower = line.lowercased()
        if blockedPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        return true
    }
}
