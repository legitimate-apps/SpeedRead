//  AttachmentMarkers.swift
import Foundation

/// U+FFFC OBJECT REPLACEMENT CHARACTER is what text systems write where a document holds
/// something that isn't text, such as a picture. `Book.tokenize` splits on whitespace only, so
/// each one left in a book's text is a word: RSVP flashes it and the reader shows a box.
///
/// PDFKit's page text has them since OS 27 for some PDFs: the bundled sample, which has three
/// pictures, gets three, while a PDF drawn with one picture by Core Graphics gets none. Every way of
/// reading a page's text returns them, so they have to come out here.
enum AttachmentMarkers {
    /// A line holding only markers goes entirely, and a marker between words becomes the space
    /// that separates them. Text with no marker comes back untouched, so books that never had
    /// one keep their exact text and word positions.
    nonisolated static func removed(from text: String) -> String {
        guard text.unicodeScalars.contains("\u{FFFC}") else { return text }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard line.unicodeScalars.contains("\u{FFFC}") else { return String(line) }
                let words = line.replacingOccurrences(of: "\u{FFFC}", with: " ", options: .literal)
                    .split(whereSeparator: \.isWhitespace)
                return words.isEmpty ? nil : words.joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}
