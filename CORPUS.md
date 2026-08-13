# CORPUS — SpeedRead

*What this project IS, what we are trying to do, and what governs it.* Numbered so points can be
referenced and argued with individually. **Living document: revise points in place — do not append.**
Stable content first, volatile last. How-to-work-here lives in `CLAUDE.md`; facts we learned live in
the memory dir.

---

## 1. Thesis

**Speed-reading should be a mode you drop into mid-sentence, not a separate app you migrate to.**

Every RSVP app makes you leave your book to use it. SpeedRead makes the two ways of reading the same
book one continuous act: read normally, tap any word, and that word is where the RSVP stream starts.
Close it, and the reader is already scrolled to where you stopped, with that word marked red. Your
position is a single number that follows you across phone, iPad and watch.

The bet: the reason people bounce off speed-reading is not the technique, it's the friction of
switching into it. Remove the switch and the technique gets used.

## 2. What it is, concretely

1. A SwiftUI e-reader for **iPhone, iPad and Apple Watch**, live on the App Store as
   "SpeedRead RSVP: books in a day" under Legitimate LLC.
2. **Two reading modes over one book**: a classic paragraph reader with tappable words, and an RSVP
   stream (100–1500 WPM) with ORP alignment so the focal letter lands where the eye already is.
3. **Formats**: EPUB, PDF, TXT, RTF — all parsed in-process. Zero third-party dependencies; the
   EPUB reader is a pure-Swift ZIP/deflate implementation over Apple's Compression framework.
4. **A bookish, physical design language** — coloured spines on a wooden shelf, parchment/sepia/night
   themes, serif type. The app should feel like a small private library, not a document viewer.
5. **A remote-catalog client** (OPDS, shipped in 1.1) so the library is not limited to what you
   sideload. See §5.

## 3. Design principles

1. **The word is the unit of interaction.** Anything the user wants to do — resume, bookmark,
   highlight, jump into RSVP — is addressed to a word, not a page, offset or percentage.
2. **No mode switch costs the reader their place.** Every transition is position-preserving in both
   directions. A transition that loses position is a bug, not a tradeoff.
3. **Skeuomorphic warmth, modern mechanics.** The surface is bookish; the implementation is current
   Swift (SwiftUI, SwiftData, `@Observable`, structured concurrency). Neither excuses the other.
4. **Ship no dependencies.** Everything is in the Apple SDKs. This is a deliberate constraint on
   what features are worth having.
5. **The watch is a real client, not a companion widget.** See §4.

## 4. Architectural invariants

These are testable statements. Breaking one is a defect regardless of what it enables.

1. **The word index is the universal coordinate.** `Book.tokenize(_:)` is the single source of truth
   for tokenization; reader, RSVP, watch and sync all address the same index space.
2. **Tokens are persisted, never recomputed per access** (`Book.tokenizedWords`).
3. **RSVP close is atomic**: `snapshotIndexAndPause()` → save → dismiss. `stop()` zeros
   `currentIndex` and must never precede a read-for-persistence.
4. **Position is last-write-wins across devices** via `updateApplicationContext`; book payloads go
   `sendMessage` with a `transferFile` fallback.
5. **Tappable words are `Button`s**, never `onTapGesture` — Voice Control, focus and keyboard
   navigation depend on it.
6. **Layout timing is expressed with `.task(id:)`**, never `DispatchQueue.main.asyncAfter`.

## 5. Standing goals

These are the operator's named priorities. They outrank backlog items.

1. **The Apple Watch surface is first-class, and stays that way.** It must be genuinely tested and
   actively maintained — not a demo that rots between releases. Concretely: the watch library, RSVP
   via the Digital Crown, and the phone↔watch sync path each carry real automated coverage, and a
   watch regression blocks a release the same way a phone regression does.
   *Current state (2026-08-13): coverage went from effectively zero — one assertion-free generated test — to 15 real tests plus an end-to-end paired-simulator verification of the position path (apply, stale-reject, and a delivery control). The `--debug-sync-position-index/-timestamp` DEBUG hooks exist so that run stays repeatable.*

2. **Read your own Calibre library from SpeedRead.** The headline outcome is simple: open SpeedRead,
   see your library, read it. Build this **generically against OPDS / Calibre-Web** so it works for
   any server, with **Calibre-Web-NextGen (CWNG)** as the recommended, best-supported path.
   - CWNG is a **separate project** that SpeedRead **offers support for**. Light touch — mention it,
     don't advertise it. No co-branding, no dependency on it existing.
   - Ship a **brief** in-app tutorial for connecting to your own **local** CWNG instance (finding the
     URL, http-on-LAN, auth), plus a link to CWNG and a one-line note that it continues
     Calibre-Web-Automated, which continues janeczku/calibre-web.
   - A fuller, general setup tutorial is **out of scope for this version and operator-gated** — see
     §8.1.
   *Groundwork exists: the v1.1 OPDS client already does multi-server CRUD, browse and plain-HTTP
   LAN servers, and its integration suite ran against a live CWNG instance.*

## 6. Boundaries

1. **Not a library manager.** SpeedRead reads; Calibre and CWNG curate. Don't rebuild metadata
   editing, conversion or shelf management here.
2. **Not a sync service.** Position sync is peer-to-peer over WatchConnectivity, and remote catalogs
   are read through the user's own server. No SpeedRead account, no SpeedRead backend.
3. **No identity mixing.** The app ships under Legitimate LLC; the operator's personal identity
   appears nowhere in the repo, the binary or any listing. CWNG references are to a separate
   project, not a sibling brand.

## 7. Release posture

1. Live: **1.1 (build 2)**, since 2026-05-21. Staged and deliberately held: **1.2 (build 3)** —
   user-facing-identical to 1.1, so submitting it would burn an App Review cycle on a no-op.
2. **A release must contain real user-facing change.** Before submitting, diff the candidate's
   *source* against the live build's source, not the version number.
3. The current top candidate for making 1.2 worth shipping: the **iPad layout defect** (the library
   renders in roughly the top-left eighth of an iPad screen — live today on a universal app).

## 8. Open TODOs

1. **Full CWNG setup tutorial — operator-gated.** The general "how to stand up Calibre-Web-NextGen"
   walkthrough is the operator's to write; SpeedRead ships only the brief local-instance version
   (§5.2) and leaves a slot to link the fuller one later.