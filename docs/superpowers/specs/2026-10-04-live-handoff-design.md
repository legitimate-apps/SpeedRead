# Live phone↔watch handoff — design

**Status:** product decisions by the operator 2026-10-04 (in session); mechanics are this doc's.
**Supersedes:** in `2026-08-30-watch-position-and-navigation-design.md`, the rule that browsing is
device-local (§2) and the watch→phone *offer* (§3). Everything else there stands: three markers,
`max` for the high-water mark, the chapter hazard, the watch settings sheet.

## 1. Problem

The watch screen is too small to find your place on. The operator wants the phone to be the finder
and the two devices to behave as **one reader**:

> "whichever was moved by the human user last, that's where we resume on both devices"
> "The Apple Watch current displayed word is always the same word as the highlighted word on the
> iPhone, essentially."

And while one device is reading, the other must say so ("the phone is reading it right now"), refuse
to progress, and let the user tap to take over, at which point the device they were reading on yields.

Today neither holds. Watch→phone is a *"Continue from Apple Watch?"* banner the user must accept;
crown and chapter moves never leave the watch; and nothing tells either device that the other is
playing, so both can read the same book at once and the later save silently wins.

## 2. Decisions (operator, 2026-10-04)

| question | answer |
|---|---|
| What moves the shared place? | **Everything**: reading, word taps, crown, chapter/bookmark jumps, scrubbing |
| Where does a takeover start? | **The other device's live word.** If that proves unreliable in real testing, ask to fall back to "this device's own place". Prefer the clean option over fragile complexity |
| Where does the "is reading" card show? | **Only on the book being read**, plus a label on that book in the library. Other books stay usable |
| Watch→phone prompt | **Gone.** The phone adopts the watch's place silently |
| Library-server positions (Kobo, KOReader) | Unchanged: still an offer. *(Default stated to the operator, not asked)* |

## 3. The place model

Still three markers in one coordinate space (CORPUS §4.1), with two of them redefined:

| marker | meaning | moved by | syncs | merge |
|---|---|---|---|---|
| `browseWordIndex` (+ new `browseDate`) | **the place**: the word on screen, highlighted in the reader | every move | **yes, phone↔watch** | last-write-wins on `browseDate` |
| `lastReadWordIndex` / `lastReadDate` | where you last *read* | reading only (play, playback, close-after-play, word tap) | yes, and to the library server | last-write-wins on `lastReadDate` (unchanged) |
| `furthestReadWordIndex` | high-water mark | reading only | yes | `max` (unchanged) |

Why the place is `browseWordIndex` and not `lastReadWordIndex`:

1. **Both RSVP engines already start from `browseWordIndex`.** "Where we resume" already means it;
   it just never left the device.
2. **The library server keeps getting reading only.** A crown fidget on the watch should not move
   your Kobo. `lastReadWordIndex` keeps feeding `ServerPositionSync` exactly as now.
3. **The watch's "Back to where I was reading" keeps its job.** It restores `lastReadWordIndex`,
   which is now a synced reading marker, so it undoes an accidental crown spin made on either device.

A reading commit still sets all three (it already does). A browse sets only the place.

The SwiftData property keeps its name. Renaming it buys a migration for no behavioural gain.
`browseDate` is a new optional property (`nil` = never moved), the same lightweight migration that
`finishedAt` took.

**Reader highlight.** The red word in the classic reader is the place. On open, the reader scrolls to
the place, not to `lastReadWordIndex`. A chapter or bookmark jump in the reader moves the place (and
the watch with it). Scrolling alone selects no word and moves nothing.

## 4. Presence: who is reading

One payload carries everything. `WatchSyncLogic.PositionPayload` gains:

- `browseWordIndex`, `browseTimestamp`: the place.
- `isPlaying`: the sender is reading this book right now.
- `playStartedAt`: when that reading run began. This orders takeovers.
- `sentAt`: when the payload left the sender. This decides liveness.

Old payloads (no new keys) decode with place = reading position and `isPlaying = false`.

**Transport.** Each send goes two ways:
- `updateApplicationContext` always: durable, latest-wins, delivered whenever the counterpart runs.
- `sendMessage` (no reply handler) when `isReachable`: live. Watch→phone wakes the iOS app in the
  background; phone→watch only lands while the watch app is on screen (Apple: `WCSession.isReachable`,
  read 2026-10-04).

**When it sends.** On every local place move (crown and scrub coalesced, at most ~4/s); on play and
on pause; and while playing, a **heartbeat every 1 s** carrying the current word.

**Liveness.** A remote presence counts as live while `now - sentAt < 6 s`. Sender and receiver
clocks are both phone-synced (ASSUMED skew well under 1 s). Because liveness reads the sender's
`sentAt`, not the arrival time, a stale application context delivered late can never raise a card.
A device that goes quiet (phone locked, watch out of range, app killed) drops off within 6 s, and the
other device unlocks at the last place it heard.

**Yield.** When a device that is playing book B receives a live, playing payload for B whose
`playStartedAt` is newer than its own, it pauses at once, adopts the incoming place, and shows the
card. If its own run is newer, it ignores the payload, because the other side will yield when it
hears this one. Ties go to the phone, so the result is deterministic.

**Takeover.** "Read here" on the card seeks to the last place heard from the other device (at most
~1 s behind its live word) and plays. That is an ordinary play: a new `playStartedAt` and a heartbeat,
which makes the other device yield. No extra protocol.

**Lowering your wrist** pauses watch playback (`scenePhase != .active`), which hands the book back.
RSVP is unreadable on a dimmed screen. **Backgrounding the phone** pauses too.

## 5. Merge on receipt (pure, tested)

`LiveHandoffLogic` (one file, symlinked into both targets per CORPUS §4.9):

- `mergePlace(local:localDate:incoming:incomingDate:) -> Int?`: the new place, or nil to keep.
- `presence(from:now:) -> RemotePresence?`: live and playing, or nil.
- `shouldYield(localRunStartedAt:incoming:isPhone:) -> Bool`
- `isLive(_:now:) -> Bool`

The reading marker keeps `WatchSyncLogic.reconcile`, now applied directly instead of offered.
`furthestRead` keeps `mergedFurthestRead`.

Persistence on receipt is coalesced: heartbeats update memory every second, but the watch's library
JSON (which holds every book's text) and the phone's SwiftData store are written on pause, on
presence loss, and at most every 5 s while live.

## 6. Surfaces

**Card (both devices)** appears when a live remote presence names the open book:
- Phone, reader and RSVP: "Reading on Apple Watch", chapter and percentage, and **Read here**. Word
  taps and playback are disabled underneath. The reader's highlight and the RSVP word follow the
  watch live, so what you see is what the watch shows.
- Watch, RSVP: "Reading on iPhone", percentage, and **Read here**. The crown is inert. The word
  underneath follows the phone.

**Library label:** the row (watch) or the book (phone) being read elsewhere carries
"Reading on iPhone" / "Reading on Apple Watch".

**Removed:** `PositionOffer`, `pendingWatchPositionOffer`, `WatchPositionOfferBanner`,
`continueFromWatch`, `shouldOfferWatchPosition`, and their tests.

## 7. Testing

- `LiveHandoffLogic`: each merge rule has a test that fails if it is swapped for another; liveness
  across the window edge; a stale context never raises a card; yield ordering both ways and the tie.
- `PositionPayload`: round trip with the new keys, and decoding of old payloads.
- `WatchSyncService` through the fake session: heartbeats go out by `sendMessage` only when
  reachable, while the context always goes; an incoming playing payload publishes presence and
  silence expires it; the phone applies a newer watch place with no offer; a yield pauses.
- Sessions: a crown/scrub move sends a place; a takeover seeks to the remote word, then plays.
- End to end on a paired iPhone + Watch simulator: watch plays → phone card within ~1 s →
  "Read here" on the phone → watch card, watch paused at the phone's word → phone pauses → watch
  resumes at that word. Screenshots as receipts.

## 8. Out of scope

iPhone↔iPad (no WatchConnectivity there) · showing the remote word stream itself at full speed ·
pushing crown fidgets to the library server.
