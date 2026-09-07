import Foundation
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch settings view decisions")
@MainActor
struct WatchSettingsViewLogicTests {
    @Test func settingsRowsAndCopyPinTheShippedNavigation() {
        #expect(WatchSettingsLogic.rows(hasChapters: false) == [
            .backToReadingPosition, .speed
        ])
        #expect(WatchSettingsLogic.rows(hasChapters: true) == [
            .chapter, .backToReadingPosition, .speed
        ])
        #expect(WatchSettingsLogic.title(for: .chapter) == "Chapter")
        #expect(WatchSettingsLogic.title(for: .backToReadingPosition) == "Back to where I was reading")
        #expect(WatchSettingsLogic.title(for: .speed) == "Speed")
        #expect(WatchSettingsLogic.speedValue(wpm: 450) == "450 WPM")
    }

    @Test func WPMIsSnappedAndClampedToTheCrownRange() {
        #expect(WatchSettingsLogic.wpmRange == 100...1_000)
        #expect(WatchSettingsLogic.wpmStep == 10)
        #expect(WatchSettingsLogic.snappedWPM(344) == 340)
        #expect(WatchSettingsLogic.snappedWPM(346) == 350)
        #expect(WatchSettingsLogic.snappedWPM(49) == 100)
        #expect(WatchSettingsLogic.snappedWPM(1_501) == 1_000)
    }

    @Test func chapterCheckmarkUsesTheChapterContainingTheVisibleWord() {
        let chapters = [
            ChapterMark(title: "One", startWordIndex: 0),
            ChapterMark(title: "Two", startWordIndex: 20),
            ChapterMark(title: "Three", startWordIndex: 40)
        ]

        #expect(WatchSettingsLogic.currentChapter(in: chapters, at: 0) == chapters[0])
        #expect(WatchSettingsLogic.currentChapter(in: chapters, at: 39) == chapters[1])
        #expect(WatchSettingsLogic.currentChapter(in: chapters, at: 40) == chapters[2])
    }
}

@Suite("Watch RSVP view decisions")
@MainActor
struct WatchRSVPViewLogicTests {
    @Test func pausedCrownBrowsingChangesOnlyTheDeviceLocalBrowseMarker() {
        let originalReadDate = Date(timeIntervalSince1970: 500)
        let book = makeBook(lastReadDate: originalReadDate)
        var library = WatchLibrary(books: [book], currentBookId: book.id)

        let needsPersistence = WatchRSVPViewLogic.recordBrowsePosition(
            book: book,
            index: 3,
            engineState: .paused,
            in: &library
        )

        #expect(needsPersistence)
        #expect(library.currentBook?.browseWordIndex == 3)
        #expect(library.currentBook?.lastReadIndex == 1)
        #expect(library.currentBook?.lastReadDate == originalReadDate)
        #expect(library.currentBook?.furthestReadWordIndex == 4)
    }

    @Test func playbackAndAMissingBookNeverMasqueradeAsBrowsePersistence() {
        let book = makeBook(lastReadDate: nil)
        let original = WatchLibrary(books: [book], currentBookId: book.id)
        var playingLibrary = original
        var missingBookLibrary = original

        #expect(!WatchRSVPViewLogic.recordBrowsePosition(
            book: book,
            index: 3,
            engineState: .playing,
            in: &playingLibrary
        ))
        #expect(!WatchRSVPViewLogic.recordBrowsePosition(
            book: nil,
            index: 3,
            engineState: .paused,
            in: &missingBookLibrary
        ))
        #expect(playingLibrary == original)
        #expect(missingBookLibrary == original)
    }

    private func makeBook(lastReadDate: Date?) -> WatchBook {
        WatchBook(
            id: UUID(),
            title: "Watch Book",
            author: "Author",
            text: "zero one two three four",
            lastReadIndex: 1,
            lastReadDate: lastReadDate,
            browseWordIndex: 1,
            furthestReadWordIndex: 4,
            wordCount: 5,
            dateAdded: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@Suite("Watch app launch decisions")
@MainActor
struct WatchAppLaunchLogicTests {
    @Test func crownDirectionArgumentSelectsOnlyTheDeterministicFixture() {
        #expect(WatchAppLaunchLogic.destination(arguments: ["SpeedReadWatch"]) == .library)
        #expect(WatchAppLaunchLogic.destination(arguments: [
            "SpeedReadWatch", WatchAppLaunchLogic.crownDirectionArgument
        ]) == .crownDirectionFixture)
    }

    @Test func productionArgumentDefaultDoesNotEnterTheUITestFixture() {
        #expect(WatchAppLaunchLogic.destination() == .library)
    }

    @Test func crownDirectionFixturePinsItsDiscriminatingPositionAndWordStream() {
        let book = WatchAppLaunchLogic.crownDirectionFixture()

        #expect(book.id == UUID(uuidString: "C0DEC0DE-0000-4000-8000-000000000008"))
        #expect(book.title == "Crown Direction Fixture")
        #expect(book.author == "SpeedRead")
        #expect(book.wordCount == 200)
        #expect(book.words.count == 200)
        #expect(book.words.first == "word000")
        #expect(book.words.last == "word199")
        #expect(book.lastReadIndex == 100)
        #expect(book.browseWordIndex == 100)
        #expect(book.furthestReadWordIndex == 100)
        #expect(book.dateAdded == Date(timeIntervalSince1970: 0))
    }
}

@Suite("Watch launch destination")
@MainActor
struct WatchLaunchDestinationTests {
    @Test("Seeded-library argument shows the library, not the fixture surface")
    func seededLibraryArgumentShowsTheLibrary() {
        #expect(WatchAppLaunchLogic.destination(arguments: ["--ui-test-seeded-library"]) == .seededLibrary)
        #expect(WatchAppLaunchLogic.destination(arguments: []) == .library)
        #expect(WatchAppLaunchLogic.destination(arguments: ["--ui-test-crown-direction"]) == .crownDirectionFixture)
    }
}
