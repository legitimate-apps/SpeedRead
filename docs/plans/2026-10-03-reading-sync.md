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

## Wire draft (CWNG, 2026-10-03, branch `feat/reading-position-sync`, unmerged, 22 tests)

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

**Matching (do the same client-side):**
- Insensitive to whitespace (strip it).
- Case-insensitive: NFKC + casefold.
- Soft hyphens and zero-width characters are dropped.
- Dash variants and curly-quote variants are folded.

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
- [ ] Sync client: server-type detection, push of committed positions, pull as an offer, anchor
  build and resolve.
- [ ] iPhone↔iPad: the same position model over Apple's own sync (it does not exist today).

## Open for the operator

- The furthest-wins policy on CWNG is product policy. The client never jumps silently, so it is
  safe, but the operator may prefer most-recent-wins.
