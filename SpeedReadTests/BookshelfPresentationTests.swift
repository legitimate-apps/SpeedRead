import SwiftUI
import Testing
@testable import SpeedRead

@Suite("Shelf and spine presentation")
@MainActor
struct BookshelfPresentationTests {
    private let storage = IsolatedDefaults()

    @Test func spineHeightScalesWithLengthAndCapsInBothSizeClasses() throws {
        let theme = ThemeManager(defaults: storage.defaults)
        for (sizeClass, width, minimum, maximum) in [
            (UserInterfaceSizeClass.compact, 60, 120, 180), (.regular, 112, 224, 300)
        ] {
    
        func render(_ words: Int) throws -> PresentationRaster {
                try PresentationRaster(BookSpineView(title: "Atlas", author: "Reader", progress: 0,
                                                      wordCount: words)
                    .environment(theme).environment(\.horizontalSizeClass, sizeClass))
            }
            let short = try render(0)
            let middle = try render(25_000)
            let full = try render(50_000)
            let oversized = try render(90_000)
            #expect(short.width == width)
            #expect(short.height == minimum)
            #expect(middle.height == (minimum + maximum) / 2)
            #expect(full.height == maximum)
            #expect(full == oversized, "Length above the cap must not stretch or change the spine")
        }
    }

    @Test func progressOnlyAddsTheBottomMarkerAndTextAndThemeActuallyRender() throws {
        let theme = ThemeManager(defaults: storage.defaults)

        func render(progress: Double = 0, title: String = "Atlas", author: String = "Reader") throws -> PresentationRaster {
            try PresentationRaster(BookSpineView(title: title, author: author, progress: progress, wordCount: 50_000)
                .environment(theme).environment(\.horizontalSizeClass, .regular))
        }
        let unread = try render()
        let started = try render(progress: 0.1)
        #expect(unread.region(x: 4..<108, y: 10..<295) == started.region(x: 4..<108, y: 10..<295))
        #expect(unread.region(x: 4..<108, y: 297..<300) != started.region(x: 4..<108, y: 297..<300))
        #expect(try render(progress: 1) == started, "The shipped marker indicates started, not proportional progress")
        #expect(try render(author: "Someone Else") != unread)
        #expect(try render(title: "Different Title") != unread)
        theme.selectedThemeId = "modern"
        #expect(try render() != unread)
    }

    @Test func shelfPlacesContentAbovePlankAndRegularWidthAddsAnEmptyBay() throws {
        let theme = ThemeManager(defaults: storage.defaults)

        func render(_ sizeClass: UserInterfaceSizeClass, populated: Bool) throws -> PresentationRaster {
            try PresentationRaster(BookshelfRowView {
                if populated {
                    Rectangle().fill(.red).frame(width: 30, height: 80)
                    Rectangle().fill(.blue).frame(width: 30, height: 100)
                }
            }.environment(theme).environment(\.horizontalSizeClass, sizeClass), width: 400)
        }
        let compactEmpty = try render(.compact, populated: false)
        let regularEmpty = try render(.regular, populated: false)
        let compact = try render(.compact, populated: true)
        let regular = try render(.regular, populated: true)
        // Empty compact shelves claim the shortest-spine bay (120) so a sparse library
        // still reads as a bookcase; populated rows are unchanged when content is taller.
        #expect(compactEmpty.height == 132)
        #expect(regularEmpty.height == 316)
        #expect(compact.height == 132)
        #expect(regular.height == 316)
        #expect(regular.region(x: 30..<370, y: 300..<316) == regularEmpty.region(x: 30..<370, y: 300..<316))
        #expect(regular.region(x: 48..<352, y: 200..<300) != regularEmpty.region(x: 48..<352, y: 200..<300))
        // The left rail remains furniture, even when content is supplied.
        #expect(regular.region(x: 0..<16, y: 30..<280) == regularEmpty.region(x: 0..<16, y: 30..<280))
        theme.selectedThemeId = "modern"
        #expect(try render(.regular, populated: false) != regularEmpty)
        #expect(try render(.compact, populated: false) != compactEmpty)
    }
}
