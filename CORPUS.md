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
4. **Position is three markers in one coordinate space, not one number.** `lastReadWordIndex`
   (reading; syncs; last-write-wins on timestamp), `browseWordIndex` (crown/chapter/scrub;
   **device-local, never syncs**) and `furthestReadWordIndex` (syncs; **merges by `max`**, so
   clock skew and out-of-order delivery cannot corrupt a high-water mark). **Reading commits;
   browsing does not.** A single number doing all three jobs is why browsing on the watch used to
   destroy the phone's reading position. Book payloads go `sendMessage` with a `transferFile`
   fallback; watch→phone position arrives as an *offer* the reader accepts, phone→watch applies
   silently.
5. **Tappable words are `Button`s**, never `onTapGesture` — Voice Control, focus and keyboard
   navigation depend on it.
6. **Layout timing is expressed with `.task(id:)`**, never `DispatchQueue.main.asyncAfter`.

## 5. Standing goals

These are the operator's named priorities. They outrank backlog items.

> ⚠️ **Read watch coverage as ATTRIBUTABLE, never as headline.** Measured across two CI runs of the
> *identical* 42-test watch suite (2026-08-31): headline moved **41.84% → 55.77%** while attributable
> moved **77.73% → 78.09%**. 316 of the 320 extra "covered" lines were GHOST — the same four files,
> named by no test, covered only because the host app rendered further into its launch path on one
> run than the other. **Scope of this claim: MEASURED ON SPEEDREAD, TWO RUNS, UNREPLICATED** — it is
> not established that host-app headline is nondeterministic in general, and a peer project's
> attempt to replicate it did not happen. What it does establish, and this stands at n=1, is that
> headline HERE can swing ~14 points with no code change, which is sufficient reason never to gate
> it: the build would go red on rendering timing rather than code quality.

1. **The Apple Watch surface is first-class, and stays that way.** It must be genuinely tested and
   actively maintained — not a demo that rots between releases. Concretely: the watch library, RSVP
   via the Digital Crown, and the phone↔watch sync path each carry real automated coverage, and a
   watch regression blocks a release the same way a phone regression does.
   *Current state (2026-08-31): the watch is now genuinely measured, which it had never been.
   Coverage on the watch app went **0.00% → 78.09% attributable** (866/1109 lines in files a test
   actually names; headline 55.77%, 1281/2297) — the first step was not writing tests but
   discovering that a `WatchHermetic` lane had never run, so tests that already existed and named
   real types had been reporting zero the whole time. `WatchLibraryView`, `WatchRSVPView`,
   `WatchSettingsView` and the `WCSessionDelegate` half of `WatchSyncService` are now driven by
   tests through a seam rather than being untestable singletons. The end-to-end paired-simulator
   verification of the position path (apply, stale-reject, and a positive delivery control) still
   stands, and the `--debug-sync-position-index/-timestamp` DEBUG hooks keep it repeatable.*

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

1. Live: **1.1 (build 2)**, since 2026-05-21. **1.2 (build 3) is staged but stale** — it was held
   because it was user-facing-identical to 1.1, and that reasoning has now been overtaken: real
   change has landed on `main` since build 3 was uploaded, so **a new build must be archived and
   attached** rather than submitting build 3 as-is.
2. **A release must contain real user-facing change.** Before submitting, diff the candidate's
   *source* against the live build's source, not the version number.
3. **The hold is over — 1.2 now has substance** (all landed 2026-08-13): the iPad library renders
   as a real adaptive bookcase instead of occupying the top-left eighth of the screen; phone↔watch
   position sync works in both directions, where it previously worked in neither; and server
   credentials no longer ship inside the binary. The remaining release work is mechanical: archive
   a new build, attach it to version 1.2, write a truthful `whatsNew`, recapture iPad screenshots
   against the fixed layout, and submit via the open review submission.

## 8. Open TODOs

1. **Full CWNG setup tutorial — operator-gated.** The general "how to stand up Calibre-Web-NextGen"
   walkthrough is the operator's to write; SpeedRead ships only the brief local-instance version
   (§5.2) and leaves a slot to link the fuller one later.