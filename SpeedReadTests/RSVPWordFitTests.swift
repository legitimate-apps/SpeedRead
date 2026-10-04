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

    @Test("A long non-word is centered and uses the width it has")
    @MainActor
    func aLongNonWordIsCentered() throws {
        let width: CGFloat = 393
        let renderer = ImageRenderer(content: RSVPWordView(
            segments: ORPCalculator.segments(for: "www.gutenberg.org/ebooks/1952"), fontSize: 36
        ))
        renderer.proposedSize = ProposedViewSize(width: width, height: 100)
        renderer.scale = 1
        let ink = try RSVPRenderProbe.wordInk(in: try #require(renderer.cgImage))
        // Before: the pivot came from "www", the URL started at the center and filled only the right half.
        #expect(abs(Double(ink.left + ink.right) / 2 - Double(width / 2)) <= 3)
        #expect(ink.left <= 24 && ink.right >= Int(width) - 24)
    }

    @Test("Passage marks are drawn above the word and nowhere else")
    @MainActor
    func passageMarksSitAboveTheWord() throws {
        func render(_ enclosures: [TextEnclosure]) throws -> (pixels: [UInt8], width: Int, height: Int) {
            let renderer = ImageRenderer(content: RSVPWordView(
                segments: ORPCalculator.segments(for: "reading"), fontSize: 36, enclosures: enclosures
            ).background(Color.black))
            renderer.proposedSize = ProposedViewSize(width: 393, height: 120)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            return (Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4)), image.width, image.height)
        }
        let plain = try render([])
        let quoted = try render([TextEnclosure(opener: "“", closer: "”", range: 0...0)])
        #expect(plain.width == quoted.width && plain.height == quoted.height)
        let changedRows = Set(stride(from: 0, to: plain.pixels.count, by: 4)
            .filter { plain.pixels[$0] != quoted.pixels[$0] }
            .map { $0 / 4 / plain.width })
        // The word is drawn centered in a frame 1.5 font sizes tall between the guides, so its
        // capitals start about a third of a font size above the middle.
        let capitals = plain.height / 2 - 36 / 3
        // Mutation: drop the overlay, and nothing changes; draw the marks on the word line, and
        // rows below the top guide change.
        #expect(!changedRows.isEmpty)
        #expect(try #require(changedRows.max()) < capitals, "rows \(changedRows.sorted()) of \(plain.height)")
    }
}
