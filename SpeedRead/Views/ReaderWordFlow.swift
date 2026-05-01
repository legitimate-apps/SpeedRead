//  ReaderWordFlow.swift
import SwiftUI

/// A horizontal flow layout that wraps its subviews to additional lines as needed.
/// Used to render paragraphs of tappable words while preserving normal text wrap.
struct WordFlowLayout: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + vSpacing
                totalWidth = max(totalWidth, rowWidth - hSpacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - hSpacing)

        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
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
