//  RSVPEngine.swift
import Foundation
import Observation

@Observable
@MainActor
final class RSVPEngine {

    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    private(set) var state: State = .idle
    private(set) var currentIndex: Int = 0
    private(set) var currentWord: String = ""
    private(set) var totalWords: Int = 0

    var wpm: Int {
        get { _wpm }
        set {
            _wpm = max(100, min(1500, newValue))
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
        return Double(currentIndex) / Double(totalWords)
    }

    func load(words: [String], startingAt index: Int) {
        stop()
        self.words = words
        self.totalWords = words.count
        let clampedIndex = max(0, min(index, words.count - 1))
        self.currentIndex = clampedIndex
        self.currentWord = words.isEmpty ? "" : words[clampedIndex]
        self.state = words.isEmpty ? .idle : .paused
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
        words = []
    }

    func seek(to index: Int) {
        guard !words.isEmpty else { return }
        let clamped = max(0, min(index, words.count - 1))
        currentIndex = clamped
        currentWord = words[clamped]
    }

    private func startPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.currentIndex < self.words.count {
                let word = self.words[self.currentIndex]
                self.currentWord = word
                let delayMs = self.timer.delay(for: word)
                let delayNs = UInt64(delayMs) * 1_000_000

                do {
                    try await Task.sleep(nanoseconds: delayNs)
                } catch {
                    return
                }

                if !Task.isCancelled {
                    self.currentIndex += 1
                }
            }

            if !Task.isCancelled {
                self.state = .paused
                if !self.words.isEmpty {
                    self.currentIndex = self.words.count - 1
                    self.currentWord = self.words[self.currentIndex]
                }
            }
        }
    }
}
