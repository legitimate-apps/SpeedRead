//  RSVPWordStrip.swift
import CoreGraphics
import Foundation

/// The words around the current one, shown while the reader drags through the book so the
/// drag reads as moving a line of text under the pivot: the strip follows the finger, the next
/// word arrives from the right, and the nearest word to the guides is always the one shown.
///
/// Presentation only. The strip never changes which word is current; the drag does that.
nonisolated struct RSVPWordStrip: Equatable, Sendable {
    /// Nearest first.
    var previous: [String] = []
    /// Nearest first.
    var next: [String] = []
    /// How far the strip is dragged toward the next word, in words: positive is forward.
    var offset: CGFloat = 0
    /// 0 is the plain RSVP word; 1 is the whole strip.
    var opacity: Double = 0

    static let hidden = RSVPWordStrip()
    /// Enough words to fill either half of a phone's width at the RSVP size.
    static let neighborCount = 4

    init(previous: [String] = [], next: [String] = [], offset: CGFloat = 0, opacity: Double = 0) {
        self.previous = previous
        self.next = next
        self.offset = offset
        self.opacity = opacity
    }

    /// The strip around `index` in `words`.
    init(words: [String], index: Int, offset: CGFloat, opacity: Double) {
        guard words.indices.contains(index) else {
            self.init()
            return
        }
        let lower = max(0, index - Self.neighborCount)
        let upper = min(words.count, index + 1 + Self.neighborCount)
        self.init(
            previous: words[lower..<index].reversed(),
            next: Array(words[(index + 1)..<upper]),
            offset: offset,
            opacity: opacity
        )
    }
}

/// Where each word of a strip sits, in unscaled points relative to the guides.
///
/// This lives outside `RSVPWordView.swift` for the same reason `RSVPWordFit` does: attributable
/// coverage is measured per file, and these decisions are what the strip's tests pin.
nonisolated struct RSVPWordStripLayout {
    /// A word's measured ORP segments.
    struct Word: Equatable {
        let before: CGFloat
        let focus: CGFloat
        let after: CGFloat

        var width: CGFloat { before + focus + after }
        /// From the word's leading edge.
        var focusCenter: CGFloat { before + focus / 2 }
    }

    let current: Word
    /// Nearest first.
    let previous: [Word]
    /// Nearest first.
    let next: [Word]
    let space: CGFloat
    let offset: CGFloat

    /// A neighbor's opacity at a full word's distance from the guides.
    static let neighborAlpha: CGFloat = 0.45

    var currentLeadingEdge: CGFloat { -current.focusCenter }

    var previousLeadingEdges: [CGFloat] {
        var edge = currentLeadingEdge
        return previous.map { word in
            edge -= space + word.width
            return edge
        }
    }

    var nextLeadingEdges: [CGFloat] {
        var edge = currentLeadingEdge + current.width + space
        return next.map { word in
            defer { edge += word.width + space }
            return edge
        }
    }

    /// The next word's pivot, relative to the current one's.
    var nextPivot: CGFloat? {
        guard let word = next.first, let edge = nextLeadingEdges.first else { return nil }
        return edge + word.focusCenter
    }

    /// The previous word's pivot, relative to the current one's.
    var previousPivot: CGFloat? {
        guard let word = previous.first, let edge = previousLeadingEdges.first else { return nil }
        return edge + word.focusCenter
    }

    /// How far the strip is moved, so that an offset of one word puts the neighbor's pivot
    /// exactly where the current word's is: the strip is continuous across a word change.
    var shift: CGFloat {
        let target = (offset > 0 ? nextPivot : previousPivot) ?? 0
        return -abs(offset) * target
    }

    /// The distance between the current pivot and its nearer neighbor's: one word's travel.
    var step: CGFloat {
        let distances = [nextPivot, previousPivot.map { -$0 }].compactMap { $0 }
        return max(distances.min() ?? current.width, 1)
    }

    /// A word's opacity from where its pivot is drawn: full at the guides, a neighbor's at a
    /// word's travel away, and gone at the edge so words never cut off hard.
    func alpha(atFocusX x: CGFloat, halfWidth: CGFloat) -> CGFloat {
        let emphasis = max(0, 1 - abs(x) / step)
        let base = Self.neighborAlpha + (1 - Self.neighborAlpha) * emphasis
        guard halfWidth > 0 else { return 0 }
        let edge = min(1, max(0, (halfWidth - abs(x)) / (halfWidth * 0.4)))
        return base * edge
    }

    /// The red pivot fades out as its word leaves the guides, so it hands over to the next word
    /// at the halfway point without a flash.
    static func pivotAlpha(offset: CGFloat, stripOpacity: Double) -> Double {
        1 - min(1, 2 * Double(abs(offset))) * stripOpacity
    }
}

/// The caption under the word while dragging: where the drag has taken the reader.
nonisolated enum RSVPScrubCaption {
    enum Direction: Equatable {
        case ahead
        case back
    }

    static func direction(from start: Int, to current: Int) -> Direction? {
        current > start ? .ahead : current < start ? .back : nil
    }

    static func text(from start: Int, to current: Int) -> String? {
        guard let direction = direction(from: start, to: current) else { return nil }
        let count = abs(current - start)
        let words = count == 1 ? "1 word" : "\(count.formatted()) words"
        return direction == .ahead ? "\(words) ahead" : "\(words) back"
    }
}
