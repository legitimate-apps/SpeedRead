import SwiftUI
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("Watch settings presentation and actions")
@MainActor
struct WatchSettingsPresentationTests {
    private let storage = IsolatedDefaults()
    private let chapters = [ChapterMark(title: "Opening", startWordIndex: 0),
                            ChapterMark(title: "Middle", startWordIndex: 20),
                            ChapterMark(title: "Ending", startWordIndex: 40)]

    @Test func rootOmitsEmptyChaptersAndForwardsSelectionAndRestoreExactlyOnce() throws {
        var selected: [ChapterMark] = []
        var restores = 0
        let engine = RSVPEngine()
        let empty = WatchSettingsView(engine: engine, chapters: [], currentWordIndex: 0,
                                      onSelectChapter: { selected.append($0) },
                                      onRestoreReadingPosition: { restores += 1 })
        #expect(empty.chapterList == nil)
        let root = WatchSettingsView(engine: engine, chapters: chapters, currentWordIndex: 39,
                                     onSelectChapter: { selected.append($0) },
                                     onRestoreReadingPosition: { restores += 1 })
        let list = try #require(root.chapterList)
        #expect(list.chapters == chapters)
        #expect(list.currentChapter == chapters[1])
        list.select(chapters[2])
        #expect(selected == [chapters[2]])
        #expect(restores == 0)
        root.restoreReadingPosition()
        #expect(restores == 1)
        #expect(selected == [chapters[2]])
    }

    @Test func rootRowsRenderChapterAvailabilityAndCurrentEngineSpeed() throws {
        let engine = RSVPEngine()

        func root(_ marks: [ChapterMark]) -> WatchSettingsView {
            WatchSettingsView(engine: engine, chapters: marks, currentWordIndex: 0,
                              onSelectChapter: { _ in }, onRestoreReadingPosition: {})
        }
        let empty = try PresentationRaster(VStack { root([]).rows }, width: 198, height: 220)
        let chapterRows = try PresentationRaster(VStack { root(chapters).rows }, width: 198, height: 220)
        #expect(empty != chapterRows, "Chapter navigation must only be offered for a chaptered book")
        engine.wpm = 750
        let faster = try PresentationRaster(VStack { root(chapters).rows }, width: 198, height: 220)
        #expect(faster != chapterRows, "The root speed row must show the current engine WPM")
    }

    @Test func chapterCheckmarkMovesAtTheBoundaryWithoutChangingOtherRows() throws {
        let before = WatchChapterListView(chapters: chapters, currentWordIndex: 39, onSelect: { _ in })
        let after = WatchChapterListView(chapters: chapters, currentWordIndex: 40, onSelect: { _ in })
        #expect(before.currentChapter == chapters[1])
        #expect(after.currentChapter == chapters[2])
        func row(_ list: WatchChapterListView, _ index: Int) throws -> PresentationRaster {
            try PresentationRaster(list.chapterLabel(chapters[index]).environment(\.colorScheme, .dark).background(.black), width: 180, height: 30)
        }
        #expect(try row(before, 0) == row(after, 0))
        #expect(try row(before, 1) != row(after, 1))
        #expect(try row(before, 2) != row(after, 2))
        #expect(try row(before, 0) != row(before, 2), "Chapter titles must be drawn")
    }

    @Test func crownDraftSnapsClampsAndOnlyDoneUpdatesEngineAndIsolatedDefaults() throws {
        let engine = RSVPEngine()
        engine.wpm = 346
        storage.defaults.set(220, forKey: "rsvpLastWPM")
        var draft = 300.0
        let control = WatchSpeedSettingsControl(engine: engine,
            wpmValue: Binding(get: { draft }, set: { draft = $0 }), defaults: storage.defaults)
        // Rendering the full control delivers onAppear; subsequent draft probes avoid remounting it.
        _ = try PresentationRaster(control, width: 198, height: 200)
        #expect(draft == 350)
        #expect(engine.wpm == 346)
        let initial = try PresentationRaster(control.controls, width: 198, height: 200)
        for (raw, expected) in [(344.0, 340.0), (346, 350), (49, 100), (1_501, 1_000)] {
            control.crownValue.wrappedValue = raw
            #expect(draft == expected)
            #expect(control.crownValue.wrappedValue == expected)
            #expect(engine.wpm == 346)
            #expect(storage.defaults.integer(forKey: "rsvpLastWPM") == 220)
        }
        let changed = try PresentationRaster(control.controls, width: 198, height: 200)
        #expect(initial != changed, "The crown changes the displayed number before saving")
        control.saveSpeed()
        #expect(engine.wpm == 1_000)
        #expect(storage.defaults.integer(forKey: "rsvpLastWPM") == 1_000)
        let reloaded = UserDefaults(suiteName: storage.name)!
        #expect(reloaded.integer(forKey: "rsvpLastWPM") == 1_000)
        // Done also normalizes a value arriving from a non-crown binding writer.
        draft = 344
        control.saveSpeed()
        #expect(engine.wpm == 340)
        #expect(reloaded.integer(forKey: "rsvpLastWPM") == 340)
    }
}
