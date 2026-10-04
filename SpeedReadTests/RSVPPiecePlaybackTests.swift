import Foundation
import Testing
#if os(watchOS)
@testable import SpeedReadWatch_Watch_App
#else
@testable import SpeedRead
#endif

@Suite("RSVP playback of long words and bounded passages")
struct RSVPPiecePlaybackTests {
    @Test @MainActor func aLongWordIsShownAPieceAtATimeOnOneWordIndex() throws {
        let engine = RSVPEngine()
        let long = "electroencephalographically"
        engine.load(words: ["a", long, "b"], startingAt: 1)
        let pieces = LongWord.pieces(of: long)
        #expect(pieces.count > 1)
        let shown = engine.currentSegments
        #expect(shown.before + shown.focus + shown.after == pieces[0])
        #expect(engine.currentWord == long, "The word, not the piece, is what VoiceOver and positions see")
        engine.seek(to: 2)
        #expect(engine.currentPiece == 0)
    }

    @Test func playbackStepsThroughPiecesThenSkipsSilentWords() throws {
        let silent: Set<Int> = [2, 3]
        let isSilent: (Int) -> Bool = { silent.contains($0) }
        let piece = try #require(RSVPPlaybackStep.next(index: 1, piece: 0, pieceCount: 2, wordCount: 6, isSilent: isSilent))
        #expect(piece == (1, 1))
        // Mutation: drop the silent skip. Playback then flashes a lone "***" for a full beat.
        let word = try #require(RSVPPlaybackStep.next(index: 1, piece: 1, pieceCount: 2, wordCount: 6, isSilent: isSilent))
        #expect(word == (4, 0))
        #expect(RSVPPlaybackStep.next(index: 5, piece: 0, pieceCount: 1, wordCount: 6, isSilent: isSilent) == nil)
        #expect(RSVPPlaybackStep.firstShown(from: 2, wordCount: 6, isSilent: isSilent) == 4)
        #expect(RSVPPlaybackStep.firstShown(from: 5, wordCount: 6, isSilent: { _ in true }) == 5,
                "A silent last word is still shown")
    }

    @Test @MainActor func playingShowsEveryPieceInOrderAndNeverASilentMark() async throws {
        let engine = RSVPEngine()
        engine.wpm = 1500
        let text = "*** electroencephalographically ***\n\nend"
        engine.load(words: BookTokenizer.tokenize(text), startingAt: 0)
        engine.annotate(TextEnclosures.scan(text))
        var frames: [String] = []
        engine.play()
        for _ in 0..<400 where engine.state == .playing || frames.isEmpty {
            let segments = engine.currentSegments
            let frame = segments.before + segments.focus + segments.after
            if frames.last != frame { frames.append(frame) }
            try await Task.sleep(for: .milliseconds(3))
        }
        #expect(frames == LongWord.pieces(of: "electroencephalographically") + ["end"])
        #expect(engine.didFinish)
    }

    @Test @MainActor func passagesApplyOnlyToTheWordsTheyWereFoundIn() {
        let engine = RSVPEngine()
        engine.load(words: ["“one", "two”", "three"], startingAt: 1)
        // Mutation: drop the count check. A stale scan would draw marks over the wrong words.
        engine.annotate(TextEnclosures.scan("“one two” three four"))
        #expect(engine.currentEnclosures.isEmpty)
        engine.annotate(TextEnclosures.scan("“one two” three"))
        #expect(engine.currentEnclosures.map(\.opener) == ["“"])
        engine.seek(to: 2)
        #expect(engine.currentEnclosures.isEmpty)
    }

    @Test @MainActor func passagesFoundOffTheMainActorArrive() async throws {
        let engine = RSVPEngine()
        let text = "say (this aside) now"
        engine.load(words: BookTokenizer.tokenize(text), startingAt: 2)
        engine.annotate(text: text)
        for _ in 0..<200 where engine.currentEnclosures.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.currentEnclosures.map(\.closer) == [")"])
    }
}
