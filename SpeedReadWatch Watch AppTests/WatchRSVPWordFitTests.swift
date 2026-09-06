import SwiftUI
import Testing
@testable import SpeedReadWatch_Watch_App

@Suite("RSVP word fitting")
struct WatchRSVPWordFitTests {
    @Test("Rendered ink stays inside padding and its focus stays under the guides",
          arguments: ["hi", "electroencephalographically", "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"])
    @MainActor
    func renderedInkFits(word: String) throws {
        let width: CGFloat = 208
        let renderer = ImageRenderer(content: RSVPWordView(
            segments: .init(before: "ii", focus: "o", after: word), fontSize: 18
        ))
        renderer.proposedSize = ProposedViewSize(width: width, height: 100)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let ink = try RSVPRenderProbe.wordInk(in: image)
        #expect(image.width == Int(width))
        #expect(ink.left >= 15)
        #expect(ink.right <= Int(width) - 16)
        #expect(abs(ink.focusCenter - Double(width / 2)) <= 1)
        #expect(ink.left < Int(width / 2) && ink.right > Int(width / 2))
    }

    @Test("Rendered long words respect the proposed screen width", arguments: [CGFloat(18), 20])
    @MainActor
    func renderedWordFits(fontSize: CGFloat) throws {
        let width: CGFloat = 208
        let renderer = ImageRenderer(content: RSVPWordView(
            segments: ORPCalculator.segments(for: "electroencephalographically"), fontSize: fontSize
        ))
        renderer.proposedSize = ProposedViewSize(width: width, height: 100)
        let image = try #require(renderer.cgImage)
        #expect(CGFloat(image.width) <= width)
        #expect(image.height > 0)
    }

}
