# Watch position model and in-book navigation — design

**Status:** approved by the operator 2026-08-30 (design and the one rename).
**Supersedes:** nothing. **Depends on:** `CORPUS.md` §4 invariants.
**Partly superseded 2026-10-04** by [live handoff](2026-10-04-live-handoff-design.md): browsing now
syncs phone↔watch, and the watch→phone offer is gone. The rest stands.

## 1. Problem

Two operator reports, one root cause.

1. *"When I long-press in a book on the watch, give me a more capable settings view"* — chapter
   navigation, a way back to my place, and WPM.
2. The deeper one, in the operator's words: *"if the user goes from page to page in the apple watch
   and lose their place they can easily get back to it. But if a user has progress on their apple
   watch… their last position from the watch should be saved and resumed on their phone."*

Those two requirements **fight each other under today's rule.** `Book.lastReadWordIndex` is a single
number that syncs last-write-wins on every change (CORPUS §4.4). So the moment you thumb through
chapters on the watch, the watch's browsing position overwrites the phone's real reading position —
and a "Go to Phone Position" button has nothing good left to return to, because your own browsing
already destroyed it.

**The single number is doing three jobs.** That is the actual defect; the settings sheet is the
surface that exposed it.

## 2. Three markers, one coordinate space

This does **not** bend CORPUS §4.1. That invariant fixes the *coordinate system* — the word index —
not the number of markers expressed in it. All three are word indices produced by `Book.tokenize(_:)`.

| marker | moved by | syncs? | merge rule |
|---|---|---|---|
| `lastReadWordIndex` *(reading)* | actually reading | yes | last-write-wins on timestamp — the existing, tested `WatchSyncLogic.reconcile` |
| `browseWordIndex` *(last browsed)* | crown, chapter jump, RSVP scrub | **no — device-local** | n/a |
| `furthestReadWordIndex` | reading only | yes | **max** |

Three deliberate choices, each load-bearing:

- **`browseWordIndex` never leaves the device.** That is the whole fix. Browsing on the watch
  becomes incapable of touching the phone, so the recall affordance always has something true to
  return to.
- **`furthestReadWordIndex` merges by `max`, not last-write-wins.** A high-water mark under `max` is
  order-independent and idempotent, so clock skew, a stale `updateApplicationContext` arriving late,
  or duplicate delivery cannot corrupt it. It is the one marker needing no timestamp reasoning.
- **`lastReadWordIndex` keeps its name.** It already *is* the reading position; renaming a SwiftData
  property on a shipping app buys a migration for no behavioural gain.

### Commit rule — what counts as "reading"

Crisp, because it has to be testable:

**Commits** — pressing play; playback advancing (throttled); closing after having played.
**Does not commit** — crown seek, chapter jump, RSVP scrub, opening a book.

Browsing to chapter 5 and *then* pressing play commits chapter 5: you chose to read there.

## 3. Cross-device flow

**Watch → phone: prompt.** The incoming position becomes a *pending offer*, not an apply. The phone
shows a dismissible banner — "Continue from Apple Watch — 34%, word 4,120" — with Continue /
Dismiss, and only when the offer is newer and materially different from the local position.

**Phone → watch: silent.** Applies straight to the reading position. Asymmetric on purpose: a modal
prompt on a 44 mm screen is worse than the problem it solves, and the watch has the recall
affordance if the result is unwanted.

This changes `WatchSyncService`'s apply path on iOS only. `WatchSyncLogic.reconcile` keeps its
current `.apply / .ignoreStale / .ignoreUnknownBook` decision; `.apply` becomes "offer" on the phone
side. The decision function stays pure and stays tested.

## 4. Watch settings sheet

Long-press in `WatchRSVPView` opens a `List`, so the Digital Crown scrolls it and each row drills
into its own crown-driven control. This matters: the crown is a single input already serving both
word-seeking and WPM, and a list is the only pattern that lets it serve several without conflict.

```
[ Chapter ]                       hidden entirely when the book has no chapters
[ Back to where I was reading ]   restores lastReadWordIndex into the cursor
[ Speed — 300 WPM ]               the existing crown control, unchanged
```

**"Back to where I was reading", not "Go to Phone Position."** Approved 2026-08-30. Under this model
those are the same number whenever the devices are in sync — but the local one also works with the
phone switched off or out of range, which is exactly when the watch is being used alone. And it
describes what the button does rather than where the number came from.

**No synthetic chapters.** When a book has no real chapter structure the row is absent, not faked.

## 5. Chapters (phase 2)

Chapters do not exist anywhere in the codebase today. `EPUBExtractor` reads the spine and joins
chapters with `"\n\n"`, discarding every boundary. Adding them touches four layers:

1. **Extraction** — `EPUBExtractor` emits chapter marks from the spine it already walks. `PDFExtractor`
   can use the PDFKit outline where one exists. TXT/RTF emit none.
2. **`Book`** — a persisted `chapters: [ChapterMark]` (title + `startWordIndex`), defaulting empty,
   exactly as `tokenizedWords` did.
3. **Sync payload** — `WatchSyncLogic.BookPayload` and `WatchBook` carry the marks.
4. **Lookup** — a pure `ChapterIndex.chapter(containing:)` / `.start(of:)`.

🚨 **The migration hazard, stated explicitly because getting it wrong is unrecoverable.** Chapter
marks must be recorded as **offsets into the existing token stream**, and tokenization must be
byte-for-byte unchanged. Today chapters are joined with `"\n\n"` and `Book.tokenize(_:)` splits on
whitespace, so recording boundaries as word offsets changes no index. If chapter extraction were to
alter the joined text even slightly, **every saved position, bookmark and highlight in every
existing book would silently shift** — the same class of failure as the EPUB chapter-loss bug, and
harder to detect. A test must pin that the token stream for the bundled sample books is identical
before and after chapters land.

## 6. Testing

Nearly all of this is pure logic and lands as attributable coverage rather than view code:

- `ReadingPositions` — the three markers and the commit rule.
- `ChapterIndex` — containing/start lookup, boundaries, empty and single-chapter books.
- Sync — `furthestRead` max-merge, the offer decision, out-of-order and duplicate delivery. Extends
  `WatchSyncLogic`, already the best-tested part of the sync path.
- `CrownSeek` — landed 2026-08-29.
- Migration — token-stream identity for the four bundled sample books.

Red-first throughout. Each marker's merge rule gets a test that fails if the rule is swapped for
either of the other two — a `max` marker that passes a last-write-wins test is pinning nothing.

## 7. Also fixed here

`crownValue` in `WatchRSVPView` is written only in `.onAppear` and never follows the engine, so
after playback the first crown detent snaps the reader back to wherever they opened RSVP. Found
2026-08-29 and deliberately left unpatched, because `browseWordIndex` is its correct home. It gets
its own red-first test.

## 8. Out of scope

Synthetic chapters for structureless books · watch-side catalog browsing · any change to the RSVP
gesture surface, settled deliberately as B15 · roadmap I16–I19 accessibility work beyond the
playback controls already exposed · CloudKit or any server-side sync (CORPUS §6.2: no SpeedRead
backend).
