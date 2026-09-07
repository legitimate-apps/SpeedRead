//  ReaderWordFlow.swift
import SwiftUI

/// A horizontal flow layout that wraps its subviews to additional lines as needed.
/// Used to render paragraphs of tappable words while preserving normal text wrap.
struct WordFlowLayout: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return WordFlowLogic.arrange(
            sizes: sizes, width: proposal.width ?? .infinity,
            hSpacing: hSpacing, vSpacing: vSpacing
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arrangement = WordFlowLogic.arrange(
            sizes: sizes, width: bounds.width, hSpacing: hSpacing, vSpacing: vSpacing
        )
        for (index, subview) in subviews.enumerated() {
            let origin = arrangement.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}

/// Splits a sequence of words into paragraph chunks based on tokens that contain
/// embedded newline characters (which is how `Book.tokenize` separates paragraphs).
/// Each chunk gets the absolute starting word index so taps map back to `book.words`.
struct ReaderParagraph: Identifiable {
    let id: Int            // starting word index, unique
    let startIndex: Int
    let words: [String]
}

enum ReaderParagraphizer {
    /// Splits a flat word array into paragraphs using a heuristic: a paragraph break
    /// occurs whenever the spacing between two consecutive words in the source text
    /// contains at least one blank line. Since `Book.tokenize` strips whitespace, we
    /// instead detect paragraph breaks using the `extractedText` directly: split on
    /// double newlines, tokenize each chunk, and align indices.
    static func paragraphs(from extractedText: String, allWords: [String]) -> [ReaderParagraph] {
        guard !allWords.isEmpty else { return [] }

        let blocks = extractedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var paragraphs: [ReaderParagraph] = []
        var cursor = 0
        for block in blocks {
            let blockWords = Book.tokenize(block)
            guard !blockWords.isEmpty else { continue }

            let end = min(cursor + blockWords.count, allWords.count)
            let slice = Array(allWords[cursor..<end])
            paragraphs.append(ReaderParagraph(id: cursor, startIndex: cursor, words: slice))
            cursor = end
            if cursor >= allWords.count { break }
        }

        if cursor < allWords.count {
            paragraphs.append(ReaderParagraph(
                id: cursor,
                startIndex: cursor,
                words: Array(allWords[cursor..<allWords.count])
            ))
        }

        return paragraphs
    }
}
