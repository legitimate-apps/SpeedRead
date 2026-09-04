//  AnnotationListLogic.swift
//  Pure decisions shared by the RSVP and reader annotation lists. In its OWN file deliberately,
//  not by style preference.
//
//  Attributable coverage is measured per FILE. A tested type sharing a file with SwiftUI
//  body markup pulls every one of those untested lines into the denominator, so the
//  metric reports worse the more logic you extract -- which is exactly backwards.
import Foundation

struct AnnotationListLogic {
    static func ordered(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted {
            if $0.wordIndex != $1.wordIndex {
                return $0.wordIndex < $1.wordIndex
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func ordered(_ highlights: [Highlight]) -> [Highlight] {
        highlights.sorted {
            if $0.startWordIndex != $1.startWordIndex {
                return $0.startWordIndex < $1.startWordIndex
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func bookmarksToDelete(
        at offsets: IndexSet,
        from displayedBookmarks: [Bookmark]
    ) -> [Bookmark] {
        offsets.map { displayedBookmarks[$0] }
    }

    static func highlightsToDelete(
        at offsets: IndexSet,
        from displayedHighlights: [Highlight]
    ) -> [Highlight] {
        offsets.map { displayedHighlights[$0] }
    }

    static func positionLabel(wordIndex: Int) -> String {
        "Word \(wordIndex + 1)"
    }

    static func rangeLabel(startWordIndex: Int, endWordIndex: Int) -> String {
        "Words \(startWordIndex + 1)–\(endWordIndex + 1)"
    }
}
