//  RSVPEngine.swift
import Foundation
import Observation

struct PlaybackPositionCommitPolicy {
    static let throttleInterval: TimeInterval = 5

    private(set) var hasPlayed = false
    private var lastCommitDate: Date?
    private var lastCommittedIndex: Int?

    mutating func reset() {
        hasPlayed = false
        lastCommitDate = nil
        lastCommittedIndex = nil
    }

    mutating func pressedPlay(at index: Int, now: Date) {
        hasPlayed = true
        lastCommitDate = now
        lastCommittedIndex = index
    }

    mutating func shouldCommitAdvance(at index: Int, now: Date) -> Bool {
        guard hasPlayed,
              index != lastCommittedIndex,
              let lastCommitDate,
              now.timeIntervalSince(lastCommitDate) >= Self.throttleInterval else {
            return false
        }
        self.lastCommitDate = now
        lastCommittedIndex = index
        return true
    }
}

@Observable
@MainActor
final class RSVPEngine {

    enum State: Equatable, Sendable {
        case idle
        case playing
        case paused
    }

    static let wpmRange = 100...1500

    private(set) var state: State = .idle
    private(set) var currentIndex: Int = 0
    private(set) var currentWord: String = ""
    private(set) var totalWords: Int = 0

    /// Set when playback completes by reaching the last word. Decoupled from
    /// `currentIndex` so progress reads as 1.0 even while the final word is
    /// still on screen.
    private(set) var didFinish: Bool = false

    /// True between `load(...)` and `stop()`. `pause()` does not change this.
    var isLoaded: Bool { totalWords > 0 }

    var wpm: Int {
        get { _wpm }
        set {
            _wpm = newValue.clamped(to: Self.wpmRange)
            timer.wpm = _wpm
        }
    }

    /// Which piece of a long word is on screen; always 0 for an ordinary word.
    private(set) var currentPiece: Int = 0
    /// The bounded passages around the current word, outermost first.
    private(set) var currentEnclosures: [TextEnclosure] = []

    private var _wpm: Int = 300
    private var words: [String] = []
    private var currentPieces: [String] = []
    private var enclosures = TextEnclosures.empty
    private var annotationTask: Task<Void, Never>?
    private var timer = WordTimer(wpm: 300)
    private var playbackTask: Task<Void, Never>?

    /// The text on screen: the current word, or the current piece of a long one.
    var currentSegments: ORPCalculator.WordSegments {
        ORPCalculator.segments(for: currentPieces.indices.contains(currentPiece) ? currentPieces[currentPiece] : currentWord)
    }

    var progress: Double {
        guard totalWords > 0 else { return 0 }
        if didFinish { return 1.0 }
        return Double(currentIndex) / Double(totalWords)
    }

    func load(words: [String], startingAt index: Int) {
        stop()
        self.words = words
        self.totalWords = words.count
        self.didFinish = false
        if words.isEmpty {
            self.state = .idle
        } else {
            show(ReadingPositionCoordinator.clampedIndex(index, wordCount: words.count))
            self.state = .paused
        }
    }

    /// Finds the book's bounded passages off the main actor and applies them when ready. The
    /// text must be the one the loaded words were tokenized from; if the counts differ the
    /// passages are dropped rather than drawn over the wrong words.
    func annotate(text: String) {
        annotationTask?.cancel()
        let loaded = words.count
        annotationTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { TextEnclosures.scan(text) }.value
            guard !Task.isCancelled, let self, self.words.count == loaded else { return }
            self.annotate(found)
        }
    }

    func annotate(_ found: TextEnclosures) {
        guard found.tokenCount == words.count else { return }
        enclosures = found
        currentEnclosures = words.isEmpty ? [] : found.enclosures(at: currentIndex)
    }

    func play() {
        guard state != .playing, !words.isEmpty else { return }
        didFinish = false
        state = .playing
        if currentPiece == 0 {
            let first = RSVPPlaybackStep.firstShown(from: currentIndex, wordCount: words.count,
                                                    isSilent: enclosures.isSilent)
            if first != currentIndex { show(first) }
        }
        startPlayback()
    }

    func pause() {
        guard state == .playing else { return }
        playbackTask?.cancel()
        playbackTask = nil
        state = .paused
    }

    /// Pauses if playing and returns the index visible to the user at this
    /// moment, in a single atomic step. Use from dismiss handlers so a
    /// concurrently-firing tick can't slide currentIndex forward between
    /// the read and the actual pause.
    func snapshotIndexAndPause() -> Int {
        let index = currentIndex
        if state == .playing {
            playbackTask?.cancel()
            playbackTask = nil
            state = .paused
        }
        return index
    }

    func togglePlayPause() {
        switch state {
        case .idle: break
        case .playing: pause()
        case .paused: play()
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        annotationTask?.cancel()
        annotationTask = nil
        state = .idle
        currentIndex = 0
        currentWord = ""
        currentPieces = []
        currentPiece = 0
        currentEnclosures = []
        enclosures = .empty
        totalWords = 0
        didFinish = false
        words = []
    }

    func seek(to index: Int) {
        guard !words.isEmpty else { return }
        show(ReadingPositionCoordinator.clampedIndex(index, wordCount: words.count))
        didFinish = false
    }

    /// Puts a word on screen, from its first piece.
    private func show(_ index: Int) {
        currentIndex = index
        currentWord = words[index]
        currentPieces = LongWord.pieces(of: currentWord)
        currentPiece = 0
        currentEnclosures = enclosures.enclosures(at: index)
    }

    private func startPlayback() {
        playbackTask?.cancel()
        let clock = ContinuousClock()
        playbackTask = Task { [weak self] in
            var nextTick = clock.now
            while !Task.isCancelled {
                guard let self, self.currentPieces.indices.contains(self.currentPiece) else { return }
                let piece = self.currentPieces[self.currentPiece]
                nextTick = nextTick.advanced(by: .milliseconds(self.timer.delay(for: piece)))

                do {
                    try await clock.sleep(until: nextTick, tolerance: .milliseconds(5))
                } catch {
                    return
                }

                if Task.isCancelled { return }
                guard let step = RSVPPlaybackStep.next(
                    index: self.currentIndex, piece: self.currentPiece, pieceCount: self.currentPieces.count,
                    wordCount: self.words.count, isSilent: self.enclosures.isSilent
                ) else { break }
                if step.index == self.currentIndex {
                    self.currentPiece = step.piece
                } else {
                    self.show(step.index)
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.state = .paused
            if !self.words.isEmpty {
                self.didFinish = true
            }
        }
    }
}

/// Where playback goes after each frame.
nonisolated enum RSVPPlaybackStep {
    /// The next piece of a long word, else the next word that is not silent. Nil at the end.
    static func next(index: Int, piece: Int, pieceCount: Int, wordCount: Int,
                     isSilent: (Int) -> Bool) -> (index: Int, piece: Int)? {
        if piece + 1 < pieceCount { return (index, piece + 1) }
        guard index + 1 < wordCount else { return nil }
        return (firstShown(from: index + 1, wordCount: wordCount, isSilent: isSilent), 0)
    }

    /// The first word from `index` that gets a beat. A silent last word is still shown, so a
    /// book never ends on nothing.
    static func firstShown(from index: Int, wordCount: Int, isSilent: (Int) -> Bool) -> Int {
        var index = index
        while index + 1 < wordCount, isSilent(index) { index += 1 }
        return index
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
