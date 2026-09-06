import SwiftUI
import Testing
@testable import SpeedRead

@Suite("RSVP word fitting")
struct RSVPWordFitTests {
    @Test("Rendered ink stays inside padding and its focus stays under the guides",
          arguments: ["hi", "electroencephalographically", "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"])
    @MainActor
    func renderedInkFits(word: String) throws {
        let width: CGFloat = 393
        let renderer = ImageRenderer(content: RSVPWordView(
            segments: .init(before: "ii", focus: "o", after: word), fontSize: 32
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

    @Test("Rendered long words respect the proposed screen width", arguments: [CGFloat(208), 393])
    @MainActor
    func renderedWordFits(width: CGFloat) throws {
        let renderer = ImageRenderer(content: RSVPWordView(
            segments: ORPCalculator.segments(for: "electroencephalographically"), fontSize: 32
        ))
        renderer.proposedSize = ProposedViewSize(width: width, height: 100)
        let image = try #require(renderer.cgImage)
        #expect(CGFloat(image.width) <= width)
        #expect(image.height > 0)
    }

    @Test("Fits either asymmetric side and never enlarges short words")
    func measuredSegmentsFit() {
        for widths: (CGFloat, CGFloat, CGFloat) in [(360, 12, 48), (48, 12, 360), (0, 600, 0), (0, 0, 0), (10, 12, 10)] {
            let fit = RSVPWordFit(before: widths.0, focus: widths.1, after: widths.2, availableWidth: 208)
            #expect(fit.leadingEdge >= -0.0001)
            #expect(fit.trailingEdge <= 208.0001)
            #expect(fit.focusCenter == 104)
            #expect(fit.scale > 0 && fit.scale <= 1)
        }
        #expect(RSVPWordFit(before: 10, focus: 12, after: 10, availableWidth: 208).scale == 1)
        #expect(RSVPWordFit(before: 10, focus: 12, after: 10, availableWidth: 0).scale == 0)
    }

    @Test("Long words fit without moving the pivot", arguments: [CGFloat(208), 393])
    func longWordsFit(width: CGFloat) {
        let fit = RSVPWordFit(before: 48, focus: 12, after: 360, availableWidth: width)
        #expect(fit.leadingEdge >= 0)
        #expect(fit.trailingEdge <= width)
        #expect(fit.focusCenter == width / 2)
        #expect(fit.scale < 1)
    }
}
