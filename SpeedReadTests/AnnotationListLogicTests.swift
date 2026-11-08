import Foundation
import SwiftData
import Testing
@testable import SpeedRead

/// Specification for the decisions shared by the four annotation lists: `BookmarkListView`
/// and `HighlightListView` (RSVP) and `ReaderBookmarkPicker` / `ReaderHighlightPicker`
/// (reader). Before this suite there were two concepts and four implementations, none of
/// whose behaviour any test named -- the only assertions on the reader pair were
/// pixel-signature smoke tests ("more than 2 distinct signatures"), which catch a crash and
/// nothing else.
@Suite("Annotation list logic")
@MainActor
struct AnnotationListLogicTests {
    @Test func anAnnotationFromAnotherReaderNamesItsReader() {
        #expect(AnnotationListLogic.sourceLabel(nil) == nil)
        #expect(AnnotationListLogic.sourceLabel("textquote") == nil)
        #expect(AnnotationListLogic.sourceLabel("koreader") == "From KOReader")
        #expect(AnnotationListLogic.sourceLabel("kobo") == "From Kobo")
        #expect(AnnotationListLogic.sourceLabel("webreader") == "From the web reader")
        #expect(AnnotationListLogic.sourceLabel("unknown") == "From your library")
    }


    @Test func onlyThisDevicesHighlightsHaveAnEditableNote() {
        let local = makeHighlight(start: 0, end: 1)
        #expect(AnnotationListLogic.noteAccess(for: local, deviceID: "me") == .editable)

        let legacy = makeHighlight(start: 0, end: 1)
        legacy.syncSource = "textquote"
        #expect(AnnotationListLogic.noteAccess(for: legacy, deviceID: "me") == .editable)
        legacy.syncOriginDevice = "me"
        #expect(AnnotationListLogic.noteAccess(for: legacy, deviceID: "me") == .editable)

        let otherDevice = makeHighlight(start: 0, end: 1)
        otherDevice.syncSource = "textquote"
        otherDevice.syncOriginDevice = "phone"
        #expect(AnnotationListLogic.noteAccess(for: otherDevice, deviceID: "me")
            == .readOnly("Added on another device. Change its note there."))

        let koreader = makeHighlight(start: 0, end: 1)
        koreader.syncSource = "koreader"
        koreader.syncOriginDevice = "me"
        #expect(AnnotationListLogic.noteAccess(for: koreader, deviceID: "me")
            == .readOnly("Added in KOReader. Change its note there."))
    }

    // MARK: - Ordering is by position in the book, never by insertion order

    @Test func bookmarksOrderByWordIndexRegardlessOfTheOrderTheyWereCreatedIn() {
        let late = makeBookmark(wordIndex: 300)
        let early = makeBookmark(wordIndex: 10)
        let middle = makeBookmark(wordIndex: 120)

        let ordered = AnnotationListLogic.ordered([late, early, middle])

        #expect(ordered.map(\.wordIndex) == [10, 120, 300])
    }

    @Test func highlightsOrderByStartWordIndexRegardlessOfTheOrderTheyWereCreatedIn() {
        let late = makeHighlight(start: 300, end: 305)
        let early = makeHighlight(start: 10, end: 12)
        let middle = makeHighlight(start: 120, end: 121)

        let ordered = AnnotationListLogic.ordered([late, early, middle])

        #expect(ordered.map(\.startWordIndex) == [10, 120, 300])
    }

    /// Swift's `sort` is introsort and is NOT stable, so two annotations sharing a position
    /// have no defined order under a bare `<` comparison -- the list could reshuffle between
    /// two renders of identical data. The tiebreak makes the ordering a total order.
    @Test func bookmarksAtTheSamePositionFallBackToCreationOrderSoTheListNeverReshuffles() {
        let older = makeBookmark(wordIndex: 42, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeBookmark(wordIndex: 42, createdAt: Date(timeIntervalSince1970: 2_000))

        #expect(AnnotationListLogic.ordered([newer, older]).map(\.id) == [older.id, newer.id])
        #expect(AnnotationListLogic.ordered([older, newer]).map(\.id) == [older.id, newer.id])
    }

    @Test func highlightsAtTheSameStartFallBackToCreationOrderSoTheListNeverReshuffles() {
        let older = makeHighlight(start: 42, end: 44, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeHighlight(start: 42, end: 44, createdAt: Date(timeIntervalSince1970: 2_000))

        #expect(AnnotationListLogic.ordered([newer, older]).map(\.id) == [older.id, newer.id])
        #expect(AnnotationListLogic.ordered([older, newer]).map(\.id) == [older.id, newer.id])
    }

    /// The implementation falls back to `id` after `createdAt`, which no other test reaches.
    /// Asserting the fallback's *mechanism* would just restate the code, so assert the property
    /// the fallback exists to provide: the result must not depend on the input's order. Two
    /// annotations can genuinely share a position and a timestamp — SwiftData assigns
    /// `createdAt` from `Date()`, and two inserts in the same run loop tick can tie.
    @Test func annotationsSharingBothPositionAndTimestampStillOrderIndependentlyOfInputOrder() {
        let instant = Date(timeIntervalSince1970: 5_000)
        let a = makeBookmark(wordIndex: 7, createdAt: instant)
        let b = makeBookmark(wordIndex: 7, createdAt: instant)

        let forwards = AnnotationListLogic.ordered([a, b]).map(\.id)
        let backwards = AnnotationListLogic.ordered([b, a]).map(\.id)

        #expect(forwards == backwards)
        #expect(Set(forwards) == Set([a.id, b.id]))

        let hA = makeHighlight(start: 7, end: 9, createdAt: instant)
        let hB = makeHighlight(start: 7, end: 9, createdAt: instant)
        #expect(AnnotationListLogic.ordered([hA, hB]).map(\.id)
                == AnnotationListLogic.ordered([hB, hA]).map(\.id))
    }

    // MARK: - Deletion resolves every offset against ONE snapshot

    /// The bug this closes: both RSVP lists deleted inside `for index in indexSet { delete(sorted[index]) }`,
    /// where `sorted` was a COMPUTED property over `book.bookmarks`. The first delete shrank the
    /// source, so the second offset indexed into a shifted array -- wrong row deleted, or out of
    /// range. Resolving all offsets up front against the array passed in makes that unrepresentable.
    @Test func deletingTwoBookmarksSelectsBothIntendedRowsAndNotTheShiftedOnes() {
        let first = makeBookmark(wordIndex: 10)
        let second = makeBookmark(wordIndex: 20)
        let third = makeBookmark(wordIndex: 30)
        let ordered = [first, second, third]

        let doomed = AnnotationListLogic.bookmarksToDelete(at: IndexSet([0, 1]), from: ordered)

        // A call site that re-derived its array between the two deletes would return
        // [first, third]: after first is gone, offset 1 addresses third.
        #expect(doomed.map(\.id) == [first.id, second.id])
        #expect(doomed.contains { $0.id == third.id } == false)
    }

    @Test func deletingTwoHighlightsSelectsBothIntendedRowsAndNotTheShiftedOnes() {
        let first = makeHighlight(start: 10, end: 11)
        let second = makeHighlight(start: 20, end: 21)
        let third = makeHighlight(start: 30, end: 31)
        let ordered = [first, second, third]

        let doomed = AnnotationListLogic.highlightsToDelete(at: IndexSet([0, 1]), from: ordered)

        #expect(doomed.map(\.id) == [first.id, second.id])
        #expect(doomed.contains { $0.id == third.id } == false)
    }

    @Test func nonAdjacentDeletionOffsetsSelectExactlyTheAddressedRows() {
        let bookmarks = [10, 20, 30, 40].map { makeBookmark(wordIndex: $0) }

        let doomed = AnnotationListLogic.bookmarksToDelete(at: IndexSet([0, 3]), from: bookmarks)

        #expect(doomed.map(\.wordIndex) == [10, 40])
    }

    // MARK: - Labels are 1-based for display over 0-based storage

    @Test func bookmarkPositionLabelCountsFromOneNotZero() {
        #expect(AnnotationListLogic.positionLabel(wordIndex: 0) == "Word 1")
        #expect(AnnotationListLogic.positionLabel(wordIndex: 41) == "Word 42")
    }

    /// Both surfaces print U+2013 EN DASH, verified in the source bytes of
    /// HighlightListView.swift and ReaderSheets.swift (e2 80 93). A hyphen-minus here would be a
    /// silent typographic regression that no rendering smoke test could see.
    @Test func highlightRangeLabelCountsFromOneAndJoinsWithAnEnDash() {
        #expect(AnnotationListLogic.rangeLabel(startWordIndex: 0, endWordIndex: 0) == "Words 1\u{2013}1")
        #expect(AnnotationListLogic.rangeLabel(startWordIndex: 41, endWordIndex: 46) == "Words 42\u{2013}47")

        let label = AnnotationListLogic.rangeLabel(startWordIndex: 41, endWordIndex: 46)
        #expect(label.contains("\u{2013}"))
        #expect(label.contains("-") == false)
    }

    // MARK: - Emptiness is decided by the annotations, on both surfaces alike

    @Test func aBookWithNoBookmarksIsEmptyAndOneBookmarkIsEnoughToPopulateTheList() {
        #expect(AnnotationListLogic.ordered([Bookmark]()).isEmpty)
        #expect(AnnotationListLogic.ordered([makeBookmark(wordIndex: 0)]).isEmpty == false)
    }

    @Test func aBookWithNoHighlightsIsEmptyAndOneHighlightIsEnoughToPopulateTheList() {
        #expect(AnnotationListLogic.ordered([Highlight]()).isEmpty)
        #expect(AnnotationListLogic.ordered([makeHighlight(start: 0, end: 1)]).isEmpty == false)
    }

    // MARK: - Helpers

    private func makeBookmark(wordIndex: Int, createdAt: Date? = nil) -> Bookmark {
        let bookmark = Bookmark(wordIndex: wordIndex, previewText: "preview \(wordIndex)")
        if let createdAt { bookmark.createdAt = createdAt }
        return bookmark
    }

    private func makeHighlight(start: Int, end: Int, createdAt: Date? = nil) -> Highlight {
        let highlight = Highlight(
            startWordIndex: start,
            endWordIndex: end,
            highlightedText: "text \(start)"
        )
        if let createdAt { highlight.createdAt = createdAt }
        return highlight
    }
}
