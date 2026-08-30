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

    private var _wpm: Int = 300
    private var words: [String] = []
    private var timer = WordTimer(wpm: 300)
    private var playbackTask: Task<Void, Never>?

    var currentSegments: ORPCalculator.WordSegments {
        ORPCalculator.segments(for: currentWord)
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
            self.currentIndex = 0
            self.currentWord = ""
            self.state = .idle
        } else {
            let clamped = index.clamped(to: 0...(words.count - 1))
            self.currentIndex = clamped
            self.currentWord = words[clamped]
            self.state = .paused
        }
    }

    func play() {
        guard state != .playing, !words.isEmpty else { return }
        state = .playing
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
        state = .idle
        currentIndex = 0
        currentWord = ""
        totalWords = 0
        didFinish = false
        words = []
    }

    func seek(to index: Int) {
        guard !words.isEmpty else { return }
        let clamped = index.clamped(to: 0...(words.count - 1))
        currentIndex = clamped
        currentWord = words[clamped]
        didFinish = false
    }

    private func startPlayback() {
        playbackTask?.cancel()
        let clock = ContinuousClock()
        playbackTask = Task { [weak self] in
            var nextTick = clock.now
            while !Task.isCancelled {
                guard let self else { return }
                if self.currentIndex >= self.words.count { break }

                let word = self.words[self.currentIndex]
                self.currentWord = word
                nextTick = nextTick.advanced(by: .milliseconds(self.timer.delay(for: word)))

                do {
                    try await clock.sleep(until: nextTick, tolerance: .milliseconds(5))
                } catch {
                    return
                }

                if Task.isCancelled { return }
                self.currentIndex += 1
            }

            guard let self, !Task.isCancelled else { return }
            self.state = .paused
            if !self.words.isEmpty {
                self.currentIndex = self.words.count - 1
                self.currentWord = self.words[self.currentIndex]
                self.didFinish = true
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
