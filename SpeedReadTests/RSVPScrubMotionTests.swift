import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import SpeedRead

@Suite("RSVP scrub motion")
struct RSVPScrubMotionTests {
    private let words = ["I", "would", "say", "a", "haunted", "house,", "and", "reach", "the", "height",
                         "of", "romantic", "felicity\u{2014}but", "that", "would", "be", "asking", "too", "much"]
    private var track: RSVPScrubTrack { RSVPScrubTrack(words: words, advance: 20, availableWidth: 400) }

    /// Where every pivot sits along the line, from the first word's.
    private func pivots(on track: RSVPScrubTrack) -> [CGFloat] {
        var positions: [CGFloat] = [0]
        for index in 0..<(track.words.count - 1) {
            positions.append(positions[index] + (track.distance(from: index, step: 1) ?? .nan))
        }
        return positions
    }

    // MARK: - Track

    @Test func theTrackPutsEachNeighborWhereTheStripDrawsIt() throws {
        // The strip measures segments with the font; the track counts characters. They must agree,
        // or the line slides out from under the finger.
        for (index, scale) in [(4, CGFloat(1)), (12, CGFloat(1))] {
            let segments = words.map(ORPCalculator.segments(for:))
            let measured = segments.map {
                RSVPWordStripLayout.Word(
                    before: CGFloat($0.before.count) * 20,
                    focus: CGFloat($0.focus.count) * 20,
                    after: CGFloat($0.after.count) * 20)
            }
            let layout = RSVPWordStripLayout(
                current: measured[index], previous: [measured[index - 1]], next: [measured[index + 1]],
                space: 20, offset: 0)
            let next = try #require(track.distance(from: index, step: 1))
            let previous = try #require(track.distance(from: index, step: -1))
            let nextPivot = try #require(layout.nextPivot)
            let previousPivot = try #require(layout.previousPivot)
            #expect(abs(next - nextPivot * scale) < 0.0001)
            #expect(abs(previous + previousPivot * scale) < 0.0001)
        }
        #expect(track.distance(from: 0, step: -1) == nil)
        #expect(track.distance(from: words.count - 1, step: 1) == nil)
        #expect(RSVPScrubTrack(words: words, advance: 0, availableWidth: 400).distance(from: 3, step: 1) == nil)
    }

    @Test func aWordTooWideForTheScreenShrinksTheLineWithIt() throws {
        let long = RSVPScrubTrack(words: ["a", String(repeating: "x", count: 40), "b"], advance: 20, availableWidth: 400)
        let wide = RSVPScrubTrack(words: long.words, advance: 20, availableWidth: 0)
        let segments = ORPCalculator.segments(for: long.words[1])
        let scale = RSVPWordFit(
            before: CGFloat(segments.before.count) * 20, focus: CGFloat(segments.focus.count) * 20,
            after: CGFloat(segments.after.count) * 20, availableWidth: 400).scale
        #expect(scale < 1)
        let shrunk = try #require(long.distance(from: 1, step: 1))
        let unscaled = try #require(wide.distance(from: 1, step: 1))
        #expect(abs(shrunk - unscaled * scale) < 0.0001)
    }

    @MainActor
    @Test func theCharacterAdvanceIsTheRSVPFontsOwn() throws {
        // Mutation: measure a different weight or design, and every word's distance is off.
        let advance = RSVPScrubTrack.characterAdvance(fontSize: 36)
        for sample in ["0000000000", "felicity\u{2014}but", "house,"] {
            let renderer = ImageRenderer(content: Text(sample).font(.rsvpWord(size: 36)).fixedSize())
            let width = try #require(renderer.uiImage).size.width
            #expect(abs(width - CGFloat(sample.count) * advance) < 1.5, "\(sample)")
        }
    }

    // MARK: - Position

    @Test func theLineMovesExactlyAsFarAsItIsMoved() {
        // However a drag is cut into moves, the line ends up exactly as far along as their sum:
        // the word under the finger stays under it.
        let pivots = pivots(on: track)
        var position = RSVPScrubPosition(index: 2)
        var total: CGFloat = 0
        for move: CGFloat in [7, 33, 61, 140, -18, 260, -95, 3, 410, -380] {
            position.move(by: move, on: track)
            total += move
            #expect(abs((pivots[position.index] - pivots[2] + position.travel) - total) < 0.0001)
            // And the word on the guides is always the nearest.
            let toNeighbor = track.distance(from: position.index, step: position.travel >= 0 ? 1 : -1) ?? .infinity
            #expect(abs(position.travel) <= toNeighbor / 2)
        }
    }

    @Test func theOffsetIsTheShareOfTheWayToTheNeighbor() throws {
        var position = RSVPScrubPosition(index: 4)
        let next = try #require(track.distance(from: 4, step: 1))
        position.move(by: next / 4, on: track)
        #expect(abs(position.offset(on: track) - 0.25) < 0.0001)
        position.move(by: -next / 2, on: track)
        let previous = try #require(track.distance(from: 4, step: -1))
        #expect(abs(position.offset(on: track) - (-next / 4) / previous) < 0.0001)
        #expect(RSVPScrubPosition(index: 4).offset(on: track) == 0)
    }

    @Test func eitherEndOfTheBookStopsTheLineAndReturnsWhatItHeldBack() throws {
        // What the end holds back is what the line visibly stretches by, so it must be exact.
        var atEnd = RSVPScrubPosition(index: words.count - 2)
        let lastStep = try #require(track.distance(from: words.count - 2, step: 1))
        let heldAtEnd = atEnd.move(by: 2_000, on: track)
        #expect(abs(heldAtEnd - (2_000 - lastStep)) < 0.0001)
        #expect(atEnd.index == words.count - 1)
        #expect(atEnd.travel == 0)

        var atStart = RSVPScrubPosition(index: 1)
        let firstStep = try #require(track.distance(from: 1, step: -1))
        let heldAtStart = atStart.move(by: -2_000, on: track)
        #expect(abs(heldAtStart - (-2_000 + firstStep)) < 0.0001)
        #expect(atStart.index == 0)
        #expect(atStart.travel == 0)

        var inside = RSVPScrubPosition(index: 5)
        #expect(inside.move(by: 30, on: track) == 0)
    }

    @Test func theStretchPastAnEndFollowsTheFingerThenStiffens() {
        let limit = ReaderConfig.RSVP.edgeStretchLimit
        #expect(RSVPScrubStretch.displayed(0) == 0)
        // Early on it gives about half the finger's travel, in the finger's direction.
        #expect(abs(RSVPScrubStretch.displayed(10) - 10 * 0.55) < 1)
        #expect(RSVPScrubStretch.displayed(-10) == -RSVPScrubStretch.displayed(10))
        // However far it is pulled, it never passes the limit, and further always gives more.
        var last: CGFloat = 0
        for pull: CGFloat in [20, 60, 150, 400, 2_000] {
            let given = RSVPScrubStretch.displayed(pull)
            #expect(given > last)
            #expect(given < limit)
            last = given
        }
    }

    // MARK: - Glide

    @Test func aSlowReleaseSettlesOntoTheWordOnTheGuides() {
        var position = RSVPScrubPosition(index: 6)
        position.move(by: -25, on: track)
        let glide = RSVPScrubGlide(
            from: position, velocity: ReaderConfig.RSVP.flingMinimumVelocity - 1, at: 10, on: track)
        #expect(glide.duration == ReaderConfig.RSVP.settleDuration)
        #expect(glide.distance == 25)
        #expect(!glide.isFinished(at: 10.1))
        #expect(glide.isFinished(at: 10 + ReaderConfig.RSVP.settleDuration))
        #expect(glide.position(at: 11, on: track) == RSVPScrubPosition(index: 6, travel: 0))
    }

    @Test(arguments: [CGFloat(1_500), -1_500, 4_000, -4_000])
    func aFlickTravelsAsFarAsTheFingerWouldInTheProjectionTimeAndLandsOnAWord(velocity: CGFloat) throws {
        let long = RSVPScrubTrack(words: Array(repeating: "reach", count: 200), advance: 20, availableWidth: 400)
        let glide = RSVPScrubGlide(from: RSVPScrubPosition(index: 100), velocity: velocity, at: 0, on: long)
        // Six characters a word here: 120 points between pivots.
        let projected = velocity * CGFloat(ReaderConfig.RSVP.flingProjection)
        #expect(abs(glide.distance - projected) <= 60)
        #expect(glide.distance.truncatingRemainder(dividingBy: 120) == 0)
        #expect(ReaderConfig.RSVP.flingDurationRange.contains(glide.duration))

        // It leaves at the finger's speed, so letting go does not lurch.
        let early = glide.position(at: 0.004, on: long)
        let earlyTravel = CGFloat(early.index - 100) * 120 + early.travel
        #expect(abs(earlyTravel / 0.004 - velocity) < abs(velocity) * 0.15)

        // It only ever moves forward through the words, and lands exactly on one.
        var last = 100
        for frame in 1...90 {
            let index = glide.position(at: Double(frame) / 60, on: long).index
            #expect(velocity > 0 ? index >= last : index <= last)
            last = index
        }
        let landed = glide.position(at: glide.duration, on: long)
        #expect(landed.travel == 0)
        #expect(CGFloat(landed.index - 100) * 120 == glide.distance)
    }

    // MARK: - Release velocity

    @Test(arguments: [CGFloat(1_500), -1_500, 400])
    func aSteadyFingerIsMeasuredAtItsSpeed(speed: CGFloat) {
        var velocity = RSVPReleaseVelocity()
        for frame in 0...30 {
            velocity.record(speed * CGFloat(frame) / 60, at: Double(frame) / 60)
        }
        #expect(abs(velocity.velocity(at: 0.5) - speed) < abs(speed) * 0.01)
    }

    @Test func aFingerThatStoppedBeforeLiftingHasNoSpeed() {
        var velocity = RSVPReleaseVelocity()
        for frame in 0...20 {
            velocity.record(-2_000 * CGFloat(frame) / 60, at: Double(frame) / 60)
        }
        // Held still for a tenth of a second: touch events stop arriving, so the last one is old.
        #expect(velocity.velocity(at: 20.0 / 60 + 0.1) == 0)
        #expect(RSVPReleaseVelocity().velocity(at: 3) == 0)
    }

    @Test func oneLateEventCannotProduceASpikeAndNoSpeedPassesTheCap() {
        var spike = RSVPReleaseVelocity()
        spike.record(0, at: 1)
        spike.record(-10, at: 1.0005)
        // Ten points in half a millisecond is 20,000 a second; never measured over less than a frame.
        #expect(abs(spike.velocity(at: 1.0005) - (-10 * 60)) < 0.001)

        var fast = RSVPReleaseVelocity()
        for frame in 0...10 { fast.record(20_000 * CGFloat(frame) / 60, at: Double(frame) / 60) }
        #expect(fast.velocity(at: 10.0 / 60) == ReaderConfig.RSVP.flingMaximumVelocity)
    }

    @Test func aFlickLandsOnThePivotNearestWhereItWasThrownAmongWordsOfEveryLength() throws {
        // Words of mixed length put pivots unevenly apart. Found on the simulator: a slow release
        // aimed one word back ran 34 words back, because the search for the landing kept going
        // once a short word took it past the target. Equal words cannot show that.
        let pivots = pivots(on: track)
        let origin = 9
        for target in stride(from: CGFloat(-1_400), through: 1_400, by: 7) {
            // A speed whose projection lands on `target`, fast enough to be a flick.
            let velocity = target / CGFloat(ReaderConfig.RSVP.flingProjection)
            guard abs(velocity) >= ReaderConfig.RSVP.flingMinimumVelocity else { continue }
            let glide = RSVPScrubGlide(from: RSVPScrubPosition(index: origin), velocity: velocity, at: 0, on: track)
            let aimedAt = pivots[origin] + target
            let nearest = try #require(pivots.min { abs($0 - aimedAt) < abs($1 - aimedAt) })
            #expect(abs((pivots[origin] + glide.distance) - nearest) < 0.0001, "target \(target)")
        }
    }

    @Test func aFlickStopsAtTheEndOfTheBook() {
        let glide = RSVPScrubGlide(from: RSVPScrubPosition(index: words.count - 3), velocity: 5_000, at: 0, on: track)
        #expect(glide.position(at: 2, on: track) == RSVPScrubPosition(index: words.count - 1, travel: 0))
    }
}
