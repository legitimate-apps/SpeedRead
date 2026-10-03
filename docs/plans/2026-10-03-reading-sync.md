# Reading sync with the user's own server — design notes

*Started 2026-10-03. The operator revised CORPUS §6.2 from "Not a sync service" to "Sync, yes; a
SpeedRead backend, no". This doc is the working record. The server half lives in the CWNG project, and the protocol was
agreed with it directly.*

## Outcome

Your place follows you between SpeedRead (iPhone, iPad, Watch) and your own library server. It
also follows you to the other readers that sync with that server: KOReader, a Kobo, and CWNG's web
reader. Read on the Kobo, open SpeedRead, and you are offered the same sentence.

## What the server has (read from CWNG origin/main `852b505a7`, 2026-10-03)

CWNG's code was read there, not here. Everything below is their report, with their file citations.

- **One account-level position feeds every reader.** KOSync rows, the Kobo reading state and the web
  reader's bookmark converge server-side. Rows that only have a percentage are served to clients
  that send `?position_kinds=locator,percentage`; older clients get `{}`.
- **KOSync** (`kosync_progress`, unique on user + document):
  - The client's `document` is the KOReader **partialMD5** of the file bytes. It resolves to the
    calibre book id through every checksum ever registered for that book.
  - The position is `progress` (an xpointer for EPUB) + `percentage`. `timestamp` is the time the
    server received it.
  - Auth is **HTTP Basic, the same credentials as OPDS**.
- **Every CWNG download registers the partialMD5 of the exact bytes it served**, OPDS included. So a
  digest computed over the downloaded bytes resolves to the book on CWNG. On a stock server, it
  matches a KOReader device holding the same file.
- **Conflict policy: furthest wins across devices; the same `device_id` may rewind.**
- **Finished** = percentage ≥ 0.99. **Always send a 0–1 fraction**: CWNG multiplies any value ≤ 1.0
  by 100.
- **Stock KOReader trusts `progress` blindly** (GotoXPointer). Anything that is not an xpointer
  mis-seeks it, and the stock sync server uses its own accounts (x-auth headers), not the OPDS
  credentials.

## Agreed protocol (dated draft 2026-10-03; the wire shape is still to be pinned by the CWNG side)

1. **Book key:** `document` = partialMD5 of the downloaded bytes, computed at download, before
   extraction. Secondary keys are the OPDS `<id>` (urn:uuid) and the acquisition-href book id. CWNG
   will accept a bare book id on PUT, for books imported before keys were captured.
2. **Transport:** KOSync paths and verbs. Detect the server type with `GET /users/auth`. CWNG
   advertises `capabilities: ["percentage", "anchor"]`.
3. **Push (CWNG only):** `{document, percentage, device, device_id, position_kind: "percentage",
   anchor: {text, before, after}}`, with no `progress`.
   - `text` is the word at the position.
   - `before`/`after` are up to 8 source words each side. They are rejoined from SpeedRead's
     hyphen-split tokens.
   - CWNG resolves the anchor in the library EPUB and derives an xpointer, a CFI and a Kobo span
     for the other readers.
4. **Pull:** `?position_kinds=locator,percentage,anchor` returns `percentage` + `anchor`, computed
   server-side from the winning position. SpeedRead searches for the anchor near `percentage` in
   its token stream and falls back to the percentage alone.
5. **Stock servers: pull only.** Read `percentage`, using `/body/DocFragment[N]` as a chapter hint.
   SpeedRead never pushes: a chapter-start xpointer with a newer timestamp would drag KOReader
   backwards, and §3.2 makes a sync that lands you elsewhere a bug.
6. **Device:** `device` is "SpeedRead (iPhone)" and so on (display-only). `device_id` is a stable
   UUID per physical device. The watch reports through the phone under the phone's `device_id`.
7. **Client UX:** only reading commits a position (CORPUS §4.4). A pulled position that differs from
   the local one is an **offer**, the same pattern as watch→phone, and is never a silent jump.

## Wire draft (CWNG, 2026-10-03, branch `feat/reading-position-sync`, merged to CWNG main 2026-10-03 22:13 UTC as PR #2458, squash 199482e7d; not yet in a CWNG release tag)

Auth is HTTP Basic with the OPDS credentials. The server is **CWNG-capable only if `"anchor"` ∈
`capabilities`**.

```
GET /kosync/users/auth
  → 200 {"authorized":"OK","capabilities":["position_kinds","percentage_push","anchor","book_id_document"]}
  (A stock server: no capabilities, and Basic gets a 401 because it wants x-auth headers.)

PUT /kosync/syncs/progress   application/json
  {"document": "<partialMD5 lowercase hex>" | "<decimal calibre id>",
   "percentage": 0.5143,                      // 0–1 only; never 0–100; not a bool
   "device": "SpeedRead (iPhone)", "device_id": "<stable UUID>",
   "position_kind": "percentage",
   "anchor": {"text": "…", "before": "…", "after": "…"}}   // optional
  - No `progress` (or null/""). `anchor` requires position_kind "percentage".
  - text: non-empty after folding, ≤200 chars. before/after: ≤600 chars or null.
  - Any violation → 400, nothing stored.
  → 200 {"document", "timestamp", "calibre_book_id"?, "calibre_book_title"?, …}
  A push that loses (furthest wins; the same device_id may rewind) still returns 200, so read the
  winner back with GET.

GET /kosync/syncs/progress/<document>?position_kinds=locator,percentage,anchor
  → 200 {"percentage", "position_kind": "locator"|"percentage", "progress": "<xpointer>"|null (ignore),
         "device", "device_id", "timestamp" (server receipt time), "calibre_book_id"?,
         "anchor"? (only when the server can prove the place in the library EPUB)}
  A miss → {}. A non-EPUB book never has an anchor.
```

**Anchor format (both directions):**
- `text` is the whole source word, punctuation attached.
- `before`/`after` are ≤8 words each side, joined with single spaces. They cross chapter
  boundaries and are clipped at the start and end of the book.
- Words are split on whitespace, and block boundaries count as whitespace.

**Matching — fold v2 (CWNG, 2026-10-03; replaces the first draft's NFKC + casefold, because Swift
has no exact equivalent of either).** Apply it per Unicode scalar, on both sides:
1. Drop whitespace, and U+00AD, U+200B, U+200C, U+200D, U+2060, U+FEFF.
2. Map U+2010–U+2015 and U+2212 to `-`.
3. Map U+2018–U+201B to `'`, and U+201C–U+201F to `"`.
4. Otherwise: NFKD of the single scalar, drop nonspacing marks (Mn), then lowercase. Diacritics are
   ignored on purpose, because precomposed and decomposed forms differ between EPUB sources.

Client: `ReadingAnchor.fold` in `SpeedRead/Sync/ReadingAnchor.swift`. Its pinned pairs were derived
from a Python transcription of the rule above, not from CWNG's code. They will be replaced by
CWNG's shared vector list when it arrives.

**Client resolution.** `AnchoredText` prepares a book once, in O(text). It searches the folded,
whitespace-free text for the full needle, then before+text, then text+after; a one-sided needle
under 16 folded bytes is skipped. It takes the occurrence nearest the reported percentage, and
refuses it when it is further than max(15% of the book, 1000 folded bytes). The result is the
first token of the matched source word. Measured 2026-10-03: CWNG's Metamorphosis anchor lands on
the right token, and every 37th position of both bundled books round-trips with no misses.

The server measured 114/116 Kindle page positions round-tripping on Metamorphosis. The two misses
are a textless cover and repeated licence boilerplate, which it correctly refused.

Finished is ≥ 0.99. `timestamp` is when the server received the push, not when the reading
happened.

## SpeedRead work list

- [x] partialMD5 port (`SpeedRead/Sync/KOReaderPartialMD5.swift`, 2026-10-03), pinned to CWNG's vectors:
  - empty → `d41d8cd98f00b204e9800998ecf8427e`
  - 1000 B of `i % 256` → `cbecbdb0fdd5cec1e242493b6008cc79`
  - 5000 B of `i % 7` → `9243bab1092e42b23119c31de4f016eb`
  - 2 MiB of `(i*31+7) % 251` → `951d6ad62a386c5d5e49f4c898e5c6c2`
  - CWNG's `metamorphosis.epub` (121089 B, sha256 `11fe3e76…22eb`) → `b208a7b085ed72b315dc87729bbd7cd5`

  The rule: read ≤1024 B at offsets 0, 1K, 4K, 16K, … 1G, stop at the first empty read, and hash
  short reads.
- [x] Capture the digest (every import), OPDS `<id>` and server book id on `Book` at download (2026-10-03).
- [ ] `ChapterMark.spineIndex` (optional, 1-based).
- [x] Anchor build and resolve, with fold v2 (2026-10-03).
- [x] Sync client (2026-10-03): server-type detection, push of committed positions, pull as an offer,
  and a per-server toggle. See "Client behaviour" below.
- [x] Joint end-to-end against a built CWNG container (2026-10-03). See "End-to-end run" below.
- [ ] iPhone↔iPad: the same position model over Apple's own sync (it does not exist today).

## Client behaviour (built 2026-10-03)

Code: `SpeedRead/Sync/` (`KOSyncClient`, `ServerPositionLogic`, `ServerPositionSync`), with the hook
in `ReadingPositionCoordinator.commit`.

- **Which books sync.** Only a book downloaded from the server, and only with that server. It is
  keyed by the digest, or by the decimal book id when it has no digest. CWNG confirmed that a GET
  for a book hidden from the account returns `{}` and names nothing.
- **Which servers.** The KOSync base is the OPDS base with its trailing `opds` replaced by `kosync`.
  `GET users/auth` is probed once per server address per launch, and only a server advertising
  `anchor` is used. A probe that gets no answer is not remembered, and the push waiting on it stays
  queued. An answer is forgotten when the server's settings are saved, because a 401 may have been
  a wrong password. Each server has its own "Sync reading position" toggle, on by default; it is
  re-checked after every network wait, so turning it off also stops a push already under way.
- **Push.** Every reading commit marks the book. The push goes out after 10 s without another commit
  (playback commits every few seconds), and immediately when the app backgrounds or the reader
  closes. Background time is ended exactly once: when the flush finishes or when iOS expires it.
  A failed push is kept for the next flush. Flushes run one at a time, because the server lets a
  device rewind its own place and an older push landing last would move it backwards.
  - A push that loses (another reader is further on) still gets a 200, so every accepted push is
    followed by a read of the winner, which can become an offer.
  - The percentage is the index over the word count.
  - An unfinished place is capped at 0.989, so reading the last page does not finish the book on
    every other reader.
  - A finished book is 1.0, with no anchor.
  - The anchor is trimmed to the server's limits, or dropped rather than risk a 400.
- **Pull.** On reader open and on returning to the foreground. The anchor is resolved in this copy;
  the percentage is the fallback. The pull becomes an offer only when another device set the place,
  after this device last read, it was not already declined at that server timestamp, and it differs
  by ≥ max(5 words, 1%) or in finished state.
- **Offer.** A banner in the reader shows where it goes ("Continue from Kobo Libra 2 — 69%", plus
  the words there). Continue commits the place: the watch follows, it is not pushed back, and a
  push queued before it is dropped. "Stay Here" remembers the declined server timestamp.
  - An offer is withdrawn when the reader reads (a commit is an answer), when the reader closes,
    when a later pull finds nothing new, and when the server's sync is turned off.
  - A pull that was in flight when its offer was withdrawn is ignored, and an older server
    position never replaces a newer offer.
- **Watch.** A position accepted from the watch is pushed by the phone under the phone's device id.

**Deliberately not done (yet):**
- Books downloaded before 2026-10-03 have neither key, so they do not sync until downloaded again.
  Matching them through an OPDS search by title and author is possible later.
- A stock KOSync server is never used. It authenticates with its own account (x-auth headers), not
  the OPDS credentials, so even pull-only support needs a separate sync-server entry. That is
  worth doing only if someone without CWNG asks.
- Sideloaded books (Files, AirDrop) never sync: no server is guaranteed to share their key.

## End-to-end run (2026-10-03, CWNG c6234f66d in a local container)

Every step was observed on a simulator against the real server. Screenshots:
`/Volumes/Crucial X8/agent-artifacts/speedread-e2e-20261003/` (outside the repo).

1. Downloading over OPDS recorded digest `d9e3a7d7…`, not the library file's `aedfc6c6…`: CWNG embeds
   metadata on download. The book id (221) carries the sync, because the server keys rows by book.
2. Tapping word 57 and closing the reader pushed it with its anchor. The server located the anchor
   as an xpointer, and the row read back under both keys.
3. A KOReader PUT at 0.7 on the library digest came back under our digest with the anchor "to".
4. Reopening the book showed "Continue from KOReader — 70%" with the right sentence. Continue
   landed on that exact token ("We have **to** try and get rid of it"), and nothing was pushed back.
5. Tapping a later word and pressing Home pushed it from the background flush, and it won.

What the run changed:
- **The percentage is measured on the server's copy for anchored positions** (CWNG 2fae7146f, on
  our proposal). The same sentence was 0.70 in KOReader and 0.772 in SpeedRead, which counts the
  front matter of its own copy, so furthest-wins compared unlike numbers. The server now derives
  the figure from the library EPUB whenever it locates the anchor; ours is only used for unanchored
  pushes. The client decides "another device" by `device_id` alone, so it needs no change.
- **The banner shows where the reader will land, in this copy's words**, which is the figure the
  header shows after Continue. Before the change, the banner read 70% and the header read 77%.
- **The banner is opaque.** The bar colour is translucent, and page text showed through it.
- **EPUB extraction no longer reads `<head>`, `<style>` or `<script>` as text.** Calibre's cover
  page put its CSS into the book's first words, and every bundled sample began with the word
  `"Cover"`. Existing books keep their stored text, and the fix applies from the next import.

## Open for the operator

- The furthest-wins policy on CWNG is product policy. The client never jumps silently, so it is
  safe, but the operator may prefer most-recent-wins. Since 2fae7146f it at least compares like
  with like.
