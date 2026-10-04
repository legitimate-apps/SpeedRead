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
position is a single number, and it should follow you wherever you read: phone, iPad, watch, and the
library server you already run. *(Shipped today: the watch only. Server sync is built and verified
end to end, not yet released — see §6.2.)*

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
4. **Position is three markers in one coordinate space, not one number.** `browseWordIndex` +
   `browseDate` is **the place**: the word on screen and the reader's red highlight, moved by
   everything (reading, taps, crown, chapter jumps, scrubbing), synced phone↔watch
   **last-write-wins on the move's time** (a place never moved dates from its last read).
   `lastReadWordIndex` is where you last *read* (reading only; syncs LWW on timestamp; the only
   marker the library server sees; the target of the watch's "Back to where I was reading").
   `furthestReadWordIndex` syncs and **merges by `max`**, so clock skew and out-of-order delivery
   cannot corrupt a high-water mark. A single number doing all three jobs is why browsing on the
   watch used to destroy the phone's reading position. The phone and watch behave as **one
   reader** (operator, 2026-10-04): each adopts the other's place silently, and while one is
   playing a book the other shows "Reading on …" on that book, cannot progress it, and takes it
   over on "Read here"; the later run wins and the other pauses without committing. Every pause
   commits, and that commit is what releases the other device. Presence is live-only
   (`sendMessage` heartbeats each second; liveness read from the sender's `sentAt`, 6 s); places
   and commits also go by application context. Book payloads go `sendMessage` with a
   `transferFile` fallback. Design: `docs/superpowers/specs/2026-10-04-live-handoff-design.md`.
5. **Tappable words are `Button`s**, never `onTapGesture` — Voice Control, focus and keyboard
   navigation depend on it.
6. **Layout timing is expressed with `.task(id:)`**, never `DispatchQueue.main.asyncAfter`.
7. **A test must be able to fail the build, and five separate things have to be true for that.**

   ```
   target exists -> in a test plan -> plan invoked by a lane -> lane executes tests
                                                             -> test aimed at the copy that
                                                                ships on that platform
   ```

   Each arrow has broken here at least once, and none announced itself: the watch unit target sat
   in no plan and read as 0.00% for months; `UI`/`WatchUI` were wired and invoked by nothing, so
   the test covering the operator's crown-direction bug could never have gone red; a non-compiling
   mutant made `xcodebuild` exit non-zero and scored as a KILL; and `SpineColorTests` cleared every
   wiring arrow while pointing at the iOS copy of a file whose watch copy held the defect.
   Enforced by `Scripts/lane-audit.py` and `Scripts/shared-source-audit.py`, each with a positive
   control that must name the real historical gap.
8. **Extracted decision logic lives in its OWN file, never beside the view it serves.** Attributable
   coverage — the number this project is gated on — is measured per file, so a tested type sharing a
   file with SwiftUI body markup drags every untested line of that markup into the denominator.
   MEASURED 2026-09-01: identical logic read 97.50%/100.00% in its own file and 5.76%/15.18% inline,
   and the inline version alone pushed the gate below its floor. Co-location makes the metric report
   worse the more logic you extract, which is exactly backwards.
9. **Files shared between the app and the watch are ONE file, symlinked — never two copies**, even
   byte-identical ones. A copy that is identical today is a copy that drifts tomorrow, and the
   drift is invisible: tests name one of the two. `SpineColor.swift`, the RSVP engine, watch sync, and the position clamp all follow this rule.

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
2. **Sync, yes; a SpeedRead backend, no.** *(Revised 2026-10-03 by the operator: this point used to
   read "Not a sync service", which ruled out the feature itself when the real constraint was only
   about who holds the data.)* Your place should follow you across your devices and to and from
   your own library server, including readers that are not SpeedRead (KOReader, a Kobo) that
   sync with that server. The constraint is where the data lives: it travels only over
   infrastructure the user already owns or Apple already provides. That means WatchConnectivity for
   the watch, Apple's own sync for the user's other Apple devices, and their own server (e.g. CWNG)
   for everything else. No SpeedRead account, no SpeedRead servers, no user data in our hands.
   - Converting a foreign position (an EPUB location, a percentage) into the word index (§4.1) is
     the hard part. It is a fidelity problem to solve, not a reason to avoid sync: by §3.2, a sync
     that lands the reader somewhere else is a bug.
   - The three-marker model (§4.4) carries over: only reading moves `lastReadWordIndex`, so
     browsing never pushes a position to the server, and a server position stays an offer.
   - *State 2026-10-03: phone↔watch sync is shipped. Sync with the library server the book came from
     (CWNG, over KOSync with text anchors) is built on `main` and passed a joint end-to-end run
     against a CWNG build: a KOReader position became an offer that landed on the same word, and
     SpeedRead's own place reached the server. It is not in a released version yet, and the server
     half was still an unmerged pull request. iPhone↔iPad still does not sync.*
3. **No identity mixing.** The app ships under Legitimate LLC; the operator's personal identity
   appears nowhere in the repo, the binary or any listing. CWNG references are to a separate
   project, not a sibling brand.

## 7. Release posture

1. **An approved build goes live.** Versions are created `AFTER_APPROVAL`; a build parked in
   `PENDING_DEVELOPER_RELEASE` is a mistake to fix, not a decision to wait on (1.3 sat approved
   for weeks that way). Current release state lives in `CLAUDE.md`, not here.
2. **A release must contain real user-facing change.** Before submitting, diff the candidate's
   *source* against the live build's source, not the version number.

## 8. Open TODOs

1. **Full CWNG setup tutorial — operator-gated.** The general "how to stand up Calibre-Web-NextGen"
   walkthrough is the operator's to write; SpeedRead ships only the brief local-instance version
   (§5.2) and leaves a slot to link the fuller one later.