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

    /// Which reader an annotation came from, for one that did not start here.
    static func sourceLabel(_ syncSource: String?) -> String? {
        switch syncSource {
        case nil, KOSyncAnnotationPush.source?: nil
        case "koreader"?: "From KOReader"
        case "kobo"?: "From Kobo"
        case "webreader"?: "From the web reader"
        default: "From your library"
        }
    }

    /// What the note editor offers for a highlight on this device.
    enum NoteAccess: Equatable {
        case editable
        /// Another device or reader made it, so only it can change the note on the server. The
        /// text says where the note can be changed.
        case readOnly(String)
    }

    static func noteAccess(for highlight: Highlight, deviceID: String) -> NoteAccess {
        if highlight.isOwned(by: deviceID) { return .editable }
        let reason = switch highlight.syncSource {
        case KOSyncAnnotationPush.source?: "Added on another device. Change its note there."
        case "koreader"?: "Added in KOReader. Change its note there."
        case "kobo"?: "Added on a Kobo. Change its note there."
        case "webreader"?: "Added in the web reader. Change its note there."
        default: "Added in another reader. Change its note there."
        }
        return .readOnly(reason)
    }

    static func positionLabel(wordIndex: Int) -> String {
        "Word \(wordIndex + 1)"
    }

    static func rangeLabel(startWordIndex: Int, endWordIndex: Int) -> String {
        "Words \(startWordIndex + 1)–\(endWordIndex + 1)"
    }
}
