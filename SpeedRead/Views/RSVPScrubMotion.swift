//  RSVPScrubMotion.swift
import CoreGraphics
import Foundation
import UIKit

/// The line of words as a track in screen points: the distance from each word's pivot to its
/// neighbor's, exactly as the strip draws them. A drag moves the line by the finger's travel, so
/// the word under the finger stays under it.
nonisolated struct RSVPScrubTrack {
    let words: [String]
    /// One character of the RSVP font at its drawn size. The font is monospaced, so a segment's
    /// width is its character count times this.
    let advance: CGFloat
    /// The width the word is drawn in. A word too long for it is scaled down, and the line with it.
    let availableWidth: CGFloat

    /// One character's width in the RSVP font (`Font.rsvpWord`).
    static func characterAdvance(fontSize: CGFloat) -> CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    /// From word `index`'s pivot to the next word's (`step` 1) or the previous word's (`step` -1),
    /// or nil when there is no such word.
    func distance(from index: Int, step: Int) -> CGFloat? {
        let neighbor = index + step
        guard words.indices.contains(index), words.indices.contains(neighbor), advance > 0 else { return nil }
        let current = ORPCalculator.segments(for: words[index])
        let other = ORPCalculator.segments(for: words[neighbor])
        let near = CGFloat(step > 0 ? current.after.count : current.before.count) + CGFloat(current.focus.count) / 2
        let far = CGFloat(step > 0 ? other.before.count : other.after.count) + CGFloat(other.focus.count) / 2
        // One space between the words.
        return (near + 1 + far) * advance * scale(of: current)
    }

    private func scale(of segments: ORPCalculator.WordSegments) -> CGFloat {
        guard availableWidth > 0 else { return 1 }
        return RSVPWordFit(
            before: CGFloat(segments.before.count) * advance,
            focus: CGFloat(segments.focus.count) * advance,
            after: CGFloat(segments.after.count) * advance,
            availableWidth: availableWidth
        ).scale
    }
}

/// Where the line of words is: the word on the guides, and how far the line has moved past it.
nonisolated struct RSVPScrubPosition: Equatable {
    var index: Int
    /// Points the line has moved past `index`'s pivot: positive toward the next word.
    var travel: CGFloat = 0

    /// Moves the line by `points`, handing the guides to whichever word's pivot is nearest them.
    /// Returns the points an end of the book held back: 0 unless the line ran out of words.
    @discardableResult
    mutating func move(by points: CGFloat, on track: RSVPScrubTrack) -> CGFloat {
        travel += points
        while travel > 0, let distance = track.distance(from: index, step: 1), travel > distance / 2 {
            index += 1
            travel -= distance
        }
        while travel < 0, let distance = track.distance(from: index, step: -1), travel < -distance / 2 {
            index -= 1
            travel += distance
        }
        guard travel != 0, track.distance(from: index, step: travel > 0 ? 1 : -1) == nil else { return 0 }
        defer { travel = 0 }
        return travel
    }

    /// How far the line is toward its neighbor, in words: the strip's offset.
    func offset(on track: RSVPScrubTrack) -> CGFloat {
        guard travel != 0, let distance = track.distance(from: index, step: travel > 0 ? 1 : -1) else { return 0 }
        return travel / distance
    }
}

/// The line's motion after the finger lifts. A flick carries on and slows to land exactly on a
/// word, the way a scroll view's content does; a slow release settles onto the nearest word.
nonisolated struct RSVPScrubGlide {
    let start: TimeInterval
    let origin: RSVPScrubPosition
    /// Points the line travels from `origin`; it ends on a word's pivot.
    let distance: CGFloat
    let duration: TimeInterval

    /// `velocity` is the line's, in points a second: positive toward the next word.
    init(from origin: RSVPScrubPosition, velocity: CGFloat, at start: TimeInterval, on track: RSVPScrubTrack) {
        self.start = start
        self.origin = origin
        let config = ReaderConfig.RSVP.self
        guard abs(velocity) >= config.flingMinimumVelocity else {
            distance = -origin.travel
            duration = config.settleDuration
            return
        }
        let landing = Self.nearestPivot(
            to: origin.travel + velocity * CGFloat(config.flingProjection), from: origin.index, on: track)
        distance = landing - origin.travel
        // An ease-out cubic starts at 3 × distance / duration: the speed the finger left at.
        let matched = TimeInterval(3 * abs(distance) / abs(velocity))
        duration = min(max(matched, config.flingDurationRange.lowerBound), config.flingDurationRange.upperBound)
    }

    /// The pivot nearest `target`, measured from `index`'s pivot along the line.
    private static func nearestPivot(to target: CGFloat, from index: Int, on track: RSVPScrubTrack) -> CGFloat {
        let step = target >= 0 ? 1 : -1
        var pivot: CGFloat = 0
        var current = index
        for _ in 0..<ReaderConfig.RSVP.flingMaximumWords {
            // Step while the target is still more than half the next step ahead. Measured as a
            // distance (not signed), a short word just past the target looks far away again, and
            // the search runs off to the bound.
            guard let distance = track.distance(from: current, step: step),
                  CGFloat(step) * (target - pivot) > distance / 2 else { break }
            pivot += CGFloat(step) * distance
            current += step
        }
        return pivot
    }

    func isFinished(at now: TimeInterval) -> Bool {
        now >= start + duration
    }

    func position(at now: TimeInterval, on track: RSVPScrubTrack) -> RSVPScrubPosition {
        var position = origin
        guard !isFinished(at: now) else {
            position.move(by: distance, on: track)
            position.travel = 0
            return position
        }
        let t = max(0, (now - start) / duration)
        let eased = 1 - pow(1 - t, 3)
        position.move(by: distance * CGFloat(eased), on: track)
        return position
    }
}

/// How far the line gives when dragged past an end of the book: it follows the finger at first,
/// then stiffens toward `ReaderConfig.RSVP.edgeStretchLimit`, the way a scroll view's edge does.
nonisolated enum RSVPScrubStretch {
    static func displayed(_ points: CGFloat) -> CGFloat {
        let limit = ReaderConfig.RSVP.edgeStretchLimit
        let given = limit * (1 - 1 / (abs(points) * 0.55 / limit + 1))
        return points < 0 ? -given : given
    }
}

/// The finger's speed as it lets go, from where it has been over the last moment. Measured across
/// a window, a touch event that lands a millisecond after the one before cannot fling the line.
nonisolated struct RSVPReleaseVelocity {
    private var samples: [(time: TimeInterval, x: CGFloat)] = []

    mutating func record(_ x: CGFloat, at time: TimeInterval) {
        samples.append((time, x))
        // Keep the newest sample from before the window: it anchors the measurement.
        let start = time - ReaderConfig.RSVP.releaseVelocityWindow
        while samples.count > 2, samples[1].time <= start { samples.removeFirst() }
    }

    /// Points a second toward positive x; 0 when the finger was still or never moved.
    func velocity(at now: TimeInterval) -> CGFloat {
        guard let last = samples.last else { return 0 }
        let config = ReaderConfig.RSVP.self
        let anchor = samples.last { $0.time <= now - config.releaseVelocityWindow } ?? samples[0]
        let span = max(now - anchor.time, config.releaseVelocityMinimumSpan)
        let speed = (last.x - anchor.x) / CGFloat(span)
        return min(max(speed, -config.flingMaximumVelocity), config.flingMaximumVelocity)
    }
}
