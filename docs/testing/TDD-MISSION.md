# TDD MISSION — SpeedRead

**Mandate (operator, 2026-08-29):** "Get it test driven… We want one hundred percent coverage. Very,
very thorough coverage. Built test-driven, and give us a very significant upgrade in code quality."

Survives compaction. Manager: Opus (this session). Implementer: Sol via `codex exec`.
Revise in place; do not append a log.

---

## 1. The honest baseline — OBSERVED 2026-08-29

150 tests, 22 suites, pass in 1.9 s. Coverage had **never been enabled** on this project (no
`.xctestplan` anywhere, no `codeCoverageEnabled` in either shared scheme). Measured with
`-enableCodeCoverage YES` + `xcrun xccov` on a leased iPhone 17 Pro / iOS 26.5 sim:

| target | line coverage | |
|---|---|---|
| `SpeedRead.app` | **17.77%** | 1486 / 8362 |
| `SpeedReadWatch Watch App.app` | **0.00%** | 0 / 1927 |
| combined shipping code | **14.4%** | 1486 / 10289 |

**The whole problem in one sentence: the SwiftUI view layer is 0% and it is 74% of the code.**

```
0%  ReaderView 1262 · RSVPView 897 · LibraryView 820 · BrowseServerView 651 · ServerEditView 396
    RemoteBookDetailView 376 · HighlightListView 336 · BookmarkListView 285 · ServerListView 247
    BookshelfRowView 193 · ThemePickerView 192 · SettingsView 168 · BookSpineView 144
    OPDSEntryRowView 143 · LibraryLayoutPreviews 140 · RSVPWordView 97 · SampleBookLoader 49
    OPDSCoverCache 16
34% WatchSyncService (pure WatchSyncLogic tested; WCSessionDelegate half not) · 35% ReaderWordFlow
45% LibraryLayoutMetrics · 71% OPDSClient · 72% EPUBExtractor
90-100% Book, OPDSAtomParser, ORPCalculator, WordTimer, PDFExtractor, models, ThemeManager
```

**Load-bearing observation:** `OnboardingView` reads 94% and `ContentView` 96% with no test naming
them — they are covered because `SpeedReadTests` is a **host-app** bundle and the host launches and
renders them. So SwiftUI `body` is reachable from the unit process with no third-party library.
That is why the coverage target is *count everything*, not *exclude the views*.

## 2. Dark spots found in the existing suite

- `SpeedReadTests/SpeedReadTests.swift` — `@Test func appLaunches()` with an **empty body**.
- `SpeedReadUITests/SpeedReadUITestsLaunchTests.swift`, both watch UI test files — Xcode
  boilerplate, **zero assertions**.
- `OPDSLiveIntegrationTests` sits in the same target as the hermetic tests and **silently no-ops**
  when its env vars are absent — a skip that looks like a pass.
- Watch app target has real tests (`WatchLibraryTests`) but they never run in the iOS lane, so the
  watch standing goal (CORPUS §5.1) has been measured at 0% coverage the whole time.

## 3. Route

| phase | outcome | state |
|---|---|---|
| 0 | Test-plan lanes (hermetic default), coverage instrument, baseline doc, dead weight removed | Sol leg 1 in flight |
| 1 | Testability seams: view-model extraction (I3/I27/I29), `WCSession` seam, Keychain seam, FS seams | queued |
| 2 | TDD the open bug backlog red-first: B2, B3, B4, B12, B15, B16, B18 | queued |
| 3 | View render coverage harness + stable a11y identifiers (I23) | queued |
| 4 | Watch lane from 0% to parity — CORPUS §5.1 says a watch regression blocks a release | queued |
| 5 | **Mutation proofing** — inject known defects, prove the suite fails. The anti-laundering gate. | queued |
| 6 | CI gate on the coverage number (needs a self-hosted runner for this repo — operator call) | queued |

## 4. Standing rules for this mission

- **Tests first from here on.** New behaviour and every bug fix starts with a failing test that was
  *watched* to fail for the right reason. Retro-fitting coverage onto existing untested code is
  allowed and required, but it is characterisation, not TDD, and must be labelled as such.
- **A test that cannot fail is worse than no test** — it inflates the number and hides the gap.
  Phase 5 exists to prove this suite can fail.
- **No third-party dependencies** (CORPUS §3.4). No ViewInspector, no SnapshotTesting.
- **No credentials in source.** This repo shipped a password in an App Store binary because a debug
  block was runtime-gated instead of `#if DEBUG`-gated.
- Machine: one `xcodebuild` at a time, leased sim + leased DerivedData, `-parallel-testing-enabled NO`.

## 8. The number we steer by — HEADLINE vs ATTRIBUTABLE vs REACH (adopted 2026-08-29)

A host-app test bundle launches the app, so every file rendered on launch reports coverage with
**zero assertions behind it**. Those lines ran; nothing fails if they break. Counting them as won is
the laundering failure in its most innocent-looking form — and it is *our own* number, not a
hypothetical. Splitting the baseline three ways:

| number | value | what it means |
|---|---|---|
| **HEADLINE** | 17.77% (1486/8362) | of all shipping iOS lines |
| **ATTRIBUTABLE** | **72.50%** (1168/1611) | of the lines in files a test actually names |
| **REACH** | **19.3%** (1611/8362) | share of the app any test even names |

**Ghost coverage: 318 lines in 4 files no test names** — `OnboardingView` 269, `ContentView` 25,
`SpeedReadApp` 15, `Theme` 9. `OnboardingView` reads 94.06% and would not fail if it broke.

⚠️ **These are the figures after the instrument was corrected twice.** It first reported
13.4% reach / 77.6% attributable, then 19.1% / 72.5%, now 19.3% / 72.5%. Both errors had the same
root: it identified each file by **globbing its basename** instead of reading the absolute `path`
that `xccov` already reports. That was wrong twice over — six sources are symlinked from
`SpeedRead/` into the watch target's `Shared/` (one file, two paths), and `SpineColor.swift` exists
twice as two genuinely different files. Every ambiguous case failed to "unknown" and was then
counted as *unreached*, silently understating reach, and it dropped precisely the best-tested code
in the repo.

**Three lessons, all durable:**
- **A classifier that fails toward a confident number is the same hazard as a test that passes
  vacuously, and neither announces itself.** The fix is a control that fires if the instrument is
  blind — `attributable.py` now asserts no row or file is lost and prints every file it could not
  classify, rather than folding them into the "unreached" bucket.
- **The first correction (resolve symlinks) treated a symptom.** It fixed one of the two ambiguity
  sources and left the other, and the run still looked clean. Only the control exposed
  `SpineColor.swift`.
- **Read the authoritative field; do not re-derive it.** `xccov` reports an absolute `path` per
  file. Inferring the file from its basename was the whole bug, and no amount of better globbing
  would have been correct.

**Bounds, not points.** REACH is an *upper* bound — a file counts as named if a test mentions any one
of the types it declares, so a file with five types and one tested type scores as fully reached.
ATTRIBUTABLE is a *lower* bound — a file exercised only indirectly (a helper driven through a tested
caller) is real coverage that lands in GHOST. The truth is bracketed by the pair, and **the movement
matters more than either absolute**.

**The re-diagnosis this forces:** the tests we have are *good* — where they reach, they cover 72.5%.
The defect is **reach**, not rigour. So the work is not "write more assertions about tested code",
it is "make ~81% of the app reachable by a test at all", which is the seam-and-extraction work of
phase 1 rather than a coverage grind. Confirmed as a real distinction by the peer session running
the identical mandate on another app, which measured the mirror image — 63.2% reach, 42.5%
attributable, i.e. *shallow rather than narrow*, and therefore a different next leg from the same
headline-ish number.

The watch target is worse on both axes and worse in a different way: 5 of 13 files ARE named by
tests, but the lane never executed, so 574 attributable lines sit at 0%. That is a wiring failure,
not a missing-tests failure, and `WatchHermetic` should convert it cheaply.

Steer by ATTRIBUTABLE and REACH; report HEADLINE so the honest global number is never hidden.
Tool: `attributable.py` (manager-side). Any file that gains coverage without gaining a test that
names it is ghost coverage and does not count.

## 5. Phase 5 in detail — the mutation gate (why the number can't be trusted without it)

Coverage says a line *ran*. It never says an assertion would have *noticed* if the line were wrong.
Phase 5 closes that, and the design is shaped by a finding from the peer session running the same
mandate on another app (2026-08-29), which is worth stating plainly because it inverts the obvious
approach:

> Their implementer reported 28 mutations applied, 28 killed, zero survivors — and the report was
> accurate. The manager then wrote **two mutations the implementer's set did not include, and both
> survived a green suite.** One was a BM25 `k1 = 1.2 → 1.9`: the covering test used an input where
> the `k1` term algebraically cancels, so it returns the same expected value for k1 = 1.2, 1.9 or 99.
> It pinned nothing, by construction.

So: **a mutation set chosen by whoever wrote the tests is biased toward mutations those tests
already catch.** Reading the implementer's table only confirms their picks. The gate must therefore
include mutations *this session* writes independently, aimed where that bias lives:

1. **Numeric constants** — for each, ask *is there an input where this term cancels out?* If yes, the
   covering test pins nothing and needs a second input where it does not cancel.
   Live candidates here: `WordTimer` multipliers (1.3 / 1.8 / 2.0 / 1.5) and its `count >= 8`
   threshold; `ORPCalculator`'s pivot table; RSVP WPM clamp bounds (100/1500);
   `LibraryLayoutMetrics` breakpoints; the reader's font-size and line-spacing defaults.
2. **Default arguments** — tests routinely pass them explicitly and therefore never exercise the
   value production actually uses. Every seam introduced in phase 1 creates one of these.
3. **Boundary flips** — `>` ↔ `>=` on `WatchSyncLogic.reconcile`'s staleness comparison, index clamps,
   and the `bookExists` / `lastReadDate == nil` branches.
4. **Deleted side effects** — remove the `save()` in the RSVP close path and confirm something fails.

Two operational traps from the same source: **confirm the mutation actually recompiled** before
believing a survival, and **do not use grep to decide whether a default is pinned** — a test that
pins a default argument does not mention the parameter name, which is the entire point of it.

### 5a. First full run — OBSERVED 2026-08-31

22 mutations, `Scripts/mutations.json`, chosen by me rather than by whoever wrote the tests.
Report: `docs/testing/mutation-report.md`. **18 KILLED · 4 SURVIVED · 0 INVALID.**

*0 INVALID is the load-bearing number.* Every mutation reached the compiler, so no verdict is a
silent pass — a mutation that fails to recompile reads exactly like one nothing pins.

The seeded prediction reproduced: `OPDSClient.init(session:)`'s default argument was included
*expecting* it to survive, and it did. A gate that reproduces a prediction is measuring something;
one that only confirms its author's picks is not.

**Three genuine gaps** (each stays `expect: KILLED`, so the gate is red until they close):

| survivor | why it survived |
|---|---|
| `WordTimer` `>= 8` long-word threshold | its only test uses `"beautiful"` — nine letters, so it passes under `>= 8` or `>= 9`. The test asserts the interior of the range; the edge is free to move. |
| `OPDSClient` accepts 3xx as success | tests cover 200/401/503 and never the 3xx band. Not just a coverage gap — a captive portal or SSO bounce answers 302 with HTML, which would be handed to `OPDSAtomParser` as a feed. |
| `init(session:)` default argument | every test passes a mock, so the one value that actually ships is the one value no test uses. |

**One survivor is an EQUIVALENT MUTANT and no test can ever kill it.** `ORPCalculator.segments`
clamps with `min(orpIndex(for: word), count - 1)`. Since `bucket(s) <= s-1` for every `s >= 1`, and
`leadingPunct + strippedLength <= count`, `orpIndex <= count - 1` always — the clamp never fires and
both forms behave identically. Proof is pure counting, so it is character-set independent; checked
empirically over 1,411,111 words (exhaustive to length 6 over an adversarial alphabet, plus 300k
random to length 40) with zero counterexamples and a tightest slack of exactly 0.

⚠️ **Not every survivor is a test gap, and I nearly briefed a delegate to write an impossible test.**
Classify before assigning: *equivalent* (unkillable — annotate with the proof), *masked* (killable,
but a redundant guard downstream hides it — find the observable that differs), or a real gap.

**That finding exposed a design flaw in the gate itself.** It exited non-zero on ANY survivor while
deliberately seeding a survivor it predicted — i.e. it could never pass. A gate that cannot pass
gets ignored within a week. It now judges each mutation against an `expect` field and fails only on
unpredicted outcomes. **Only the proven-equivalent mutant is marked expected**; annotating a real
gap as "expected" would be precisely the laundering this whole phase exists to prevent.

**Two harness repairs paid for by this run:**
- 🚨 `xcodebuild` defaults to `-collect-test-diagnostics on-failure`, which runs
  `simctl diagnose --timeout=600`. A mutation gate fails on purpose every time it *succeeds*, so
  the default punished the good outcome. Measured: mutation 1 ran its 220 tests in 3.2 s then sat
  in diagnostic collection for 4+ minutes; with `-collect-test-diagnostics never`, mutations 1 and
  2 both completed in ~75 s. It presents as a hung build with no output — i.e. it mimics a wedged
  CoreSimulator. **Use the flag in every red-heavy lane.**
- Verdicts are appended to a JSONL ledger as they land and a re-run resumes from it. The first
  attempt was SIGKILLed at mutation 3 and lost every verdict behind it. Replaying all 22 from the
  ledger now costs 0.1 s instead of ~13 minutes of simulator time.

### 5c. The resume ledger is a verification laundering vector (2026-08-31)

I built the JSONL ledger so a killed run would not lose an hour of verdicts. It has a second effect
I did not design and nearly fell into: **a re-run replays the ledger, so re-running the gate to
verify a delegate's work would have replayed the delegate's own verdicts and reported them as my
measurement.** Instant, green, and worthless — the delegate's claim and my "verification" of it
would share a single source.

The rule: **to verify someone's work, delete the ledger first, so every verdict is measured fresh.**
The gate now enforces disclosure rather than relying on me remembering — replayed verdicts are
printed as `REPLAYED from ledger, not re-measured`, marked per-row in the report, and the report
states in its header how many were not measured by that run.

General form, and it is the same shape as the equivalent-mutant trap: **a cache that makes a check
cheap also makes it possible for the check to not happen.** Any verification tool with a resume,
cache or fixture needs to say which of its answers it actually computed this time.

### 5d. Headline coverage is NONDETERMINISTIC on a host-app bundle — measured, 2026-08-31

Two CI runs, the **identical** watch suite (42 tests in 7 suites, same 2297-line denominator):

| watch lane | run A | run B | Δ |
|---|---|---|---|
| HEADLINE | 41.84% (961/2297) | 55.77% (1281/2297) | **+320 lines** |
| ATTRIBUTABLE | 77.73% (862/1109) | 78.09% (866/1109) | +4 lines |
| GHOST | 99 lines, 4 files | 415 lines, 4 files | **+316 lines** |

**316 of the 320 extra "covered" lines are GHOST** — the same four files, named by no test, covered
only because the host app rendered further into its launch path on one run than on the other. So
headline swings ~14 percentage points run-to-run for free, while attributable moves a third of a
point.

⚠️ **Evidence class: MEASURED, one project, two runs, UNREPLICATED.** The mechanism (launch-path
rendering varies, and it lands entirely in GHOST) explains it and generalises plausibly, but
plausible is not measured. Cite this as "headline swung 14 points on SpeedRead with no code change",
never as "host-app headline is nondeterministic". The distinction matters because the *caution* is
already actionable at n=1 — it correctly stops anyone gating headline — while the *generalisation*
needs a second project, and only the generalisation is currently unsupported.

Three consequences, and the first two are the reason this is in the ledger rather than a footnote:

1. **Gating on headline would make CI flaky** — a 14-point free swing dwarfs any plausible
   threshold margin, so the build would go red on rendering timing rather than on code quality.
2. **Headline movement between two runs is not evidence of anything.** I read the earlier run,
   saw the watch at 41.84%, and told the operator it had "dropped, because leg 5 grew the watch
   codebase faster than coverage followed". That explanation was wrong and I should have caught it
   from the numbers I was already holding: **the denominator was 2297 in BOTH runs**, so codebase
   growth could not have been the cause. I reached for a plausible story instead of checking that
   my evidence was consistent with it.
3. It is the strongest empirical vindication available of the operator's decision to gate
   attributable and merely report headline. The split was justified on principle (GHOST lines have
   no assertions behind them); this shows the principle has a measurable cost attached.

## 5b. CLOSED — an empty test target in no plan (OBSERVED 2026-08-31, closed 2026-09-01)

`SpeedReadWatch Watch AppUITests` exists as a target in `SpeedRead.xcodeproj`, its source directory
is **empty** (leg 1 deleted the assertion-free Xcode boilerplate), and it is referenced by **no
`.xctestplan`**. So it runs in no lane and appears in no report, while still reading on the target
list as "we have watch UI tests".

Found by applying a check the peer-project TDD session made mechanical: **diff the project's test targets
against the union of the test plans' target lists.** They ran it by hand, cleared the target they
suspected, and their script then found a second orphan they had missed — which is the argument for
automating it rather than eyeballing it.

**Target existence, test existence and plan membership are three different facts**, and reports
conflate them in both directions: this project's watch unit tests were real but unwired and read as
0.00%; this target is wired to nothing and reads as present.

**Revised 2026-08-31 — WIRE it, do not delete it.** I had queued deletion as dead scaffolding, then
checked what XCUITest can do on watchOS: `XCUIDevice.shared.rotateDigitalCrown(delta:)` exists on the
WatchSimulator platform, and its sign is documented as the user-facing scroll direction, already
adjusted for crown orientation. That makes this empty target the only place the project's last
ASSUMED link can be closed — the operator's crown-direction bug is pinned at the unit level
(`CrownSeek`), but the COMPOSITION of SwiftUI's `.digitalCrownRotation` binding with that inverted
mapping, which is the layer the operator actually experienced, is verified by nobody.

✅ **Wired in leg 8** — `SpeedReadWatch Watch AppUITests/CrownDirectionUITests.swift` exists and the
target is enabled in `WatchUI.xctestplan`. But see §5j: being in a plan turned out not to be enough.

## 5e. A delegate's confident finding inherits the manager's assumption (2026-08-31)

Leg 8 wired the dormant watch UI target and drove `XCUIDevice.rotateDigitalCrown` against the real
SwiftUI composition — the first time anything in this project measured that layer. It reported, in
bold: **the operator's Digital Crown bug is still live.** Every OBSERVED line in that report was
correct. The conclusion was wrong, and it was wrong because of *my brief*.

I had written the assertion as "a positive crown delta must move FORWARD through the book". That is
the PRE-FIX behaviour. The original build (`6363e84`) bound the crown directly —
`engine.seek(to: Int(newValue))`, so positive delta → word index rises → forward — and that is
precisely the build the operator called *"the opposite way of what I expect"*. They asked for the
inversion; `CrownSeek` applies it; the measured `+0.25 → 100→98` is the fix **working**.

So the delegate faithfully executed an assertion that encoded the exact behaviour the operator had
rejected, and returned it as a confident defect. Had I taken it at face value the next step would
have been to revert the operator's own fix.

**The lesson, and it is not "verify the delegate":** I did verify — the measurements were sound.
The failure was upstream of measurement. *An expected value written into a brief is an assumption
wearing the costume of a specification*, and every downstream OBSERVED line inherits it while
looking like independent evidence. The delegate cannot catch it, because I gave it the oracle.

Two cheap guards that would have caught this one:
- **When writing an expected value into a brief, state where it came from.** "Positive must move
  forward" had no provenance. "Positive must move forward *because…*" would have failed to complete,
  because the operator's report says the opposite.
- **When a delegate reports that a previously-fixed bug is still live, re-derive the expected value
  from the original report before believing it.** A regression and a wrong oracle look identical
  from inside the test.

One good thing survives unqualified: the composition is now measured. `rotateDigitalCrown`'s sign
convention was the open question the docs could not settle, and the run answered it — since
`index = top - crownValue`, an index falling by 2 means the bound value ROSE by 2, so a positive
XCUITest delta and a rising `.digitalCrownRotation` value agree in sign. That is a real fact the
project did not have an hour ago.

## 5f. Leg 8 — chapters + the crown closed end to end (VERIFIED BY MANAGER 2026-08-31)

Commits `fa34d37` (red) → `09411ec` → `a630c14` → `a971006`. Verified by me, not taken from the
implementer's report.

**The migration hazard held.** `BundledSampleBookTests.swift` is byte-identical (sha checked) and
appears in **no** leg-8 commit — so the exact token counts (9,173 / 25,153 / 32,036 / 187), the
character counts and the first/last tokens all still pin the stream, unmodified, through an EPUB
extractor rewrite. A new proof additionally fingerprints the raw text and the length-framed token
sequence with SHA-256.

**Both hazards I had failed to name in the brief were real, and both are now pinned.**
- *Hyphen offsets.* `Book.tokenize` splits hyphenated words, so offsets counted as whitespace words
  drift after the first hyphen — silently, because the token stream is unchanged and every existing
  guard still passes. The implementer hit exactly this between `Book.tokenize` and `WatchBook.words`
  (`self-awareness` was one token on the watch, two on the phone) and closed it by compiling one
  canonical tokenizer into both targets. The pinning test is better than the one I specified: it
  first asserts the fixture *exercises* the hazard (canonical count > whitespace count) before
  asserting `book.words[mark.startWordIndex] == first token of the chapter`. Without that control it
  could pass on a hyphen-free fixture and prove nothing.
- *Empty chapters.* A spine item with no text shares a `startWordIndex` with the next chapter.
  Semantics chosen and pinned: the LAST mark at a coordinate owns the first real token, and
  next/previous use strict comparisons so zero-width peers are skipped. Explicitly word-position
  navigation, not table-of-contents traversal — recorded because it is a product choice, and a
  future decision to make equal-offset entries individually selectable needs mark-identity
  navigation instead.

**The crown is OBSERVED, and it is the project's last ASSUMED link closing.** The previously dormant
watch UI target now runs in its own `WatchUI.xctestplan` (kept out of `WatchHermetic` so the mutation
gate does not relaunch an XCUITest 22 times), drives `XCUIDevice.rotateDigitalCrown` against the real
`.digitalCrownRotation` composition, and passes: positive delta moves BACKWARD, negative FORWARD —
the inversion the operator asked for. The test carries the provenance in a comment so nobody
"corrects" it back to the direct mapping.

**Gate re-measured from a cleared ledger: 21 killed · 1 expected survivor · 0 INVALID · 0 unexpected**,
identical to the leg-7 run. Chapters weakened nothing.

## 5g. Leg 9 — REACH (VERIFIED BY MANAGER 2026-08-31)

The diagnosis that drove it: coverage here was **narrow, not shallow**. Attributable was strong
(83.73%) but tests only *reached* half the app, so the win was making more of it nameable rather
than asserting harder inside files already covered. 26 files were named by no test, almost entirely
the SwiftUI view layer — untestable in shape, not untested.

| | before | after |
|---|---|---|
| iOS REACH | 51.36% (29/49 files) | **62.23%** (34/51) |
| watch REACH | 47.69% (11/18) | **79.03%** (16/20) |
| combined ATTRIBUTABLE | 83.73% | **84.43%** |
| combined HEADLINE | 49.20% | 60.79% |
| tests | 283 | **304**, 0 assertion-free |

Attributable *rose* while reach expanded, which is the outcome worth wanting: the newly-reached files
arrived well covered instead of diluting the number. Gate re-measured from a cleared ledger:
21 killed / 1 expected survivor / 0 invalid / 0 unexpected.

**Real bug found while extracting, as on every previous leg** (`b622a26`): `OPDSBrowseLogic` built its
fallback search URL by appending `/opds/search/{searchTerms}` to a base URL that already ends in
`/opds`, producing `…/opds/opds/search/…`. Search against any OPDS server that does not advertise a
search link would 404 silently. Found only because the logic was pulled out of the view to be
testable — which is the argument for extraction stated better than any coverage number.

⚠️ **The leg was KILLED mid-verification and left a live mutation in `WordTimer.swift`.** See §5h.

## 5h. The recovery path failed a second time, the same way (2026-08-31)

A killed gate run left mutation 6 (`1.3 → 1.6`) applied to `SpeedRead/Engine/WordTimer.swift`. The
on-disk backup did its job and named the file. `--restore` then answered:

```
CANNOT RESTORE 6-WordTimer.swift: 2 candidates
```

Six sources are symlinked into the watch target, so `WordTimer.swift` exists at two paths and the
backup filename carried only the basename. **The recovery path failed on exactly the file family
most likely to need it, and only at the moment it was needed** — the second time this tool has had a
recovery mechanism that worked solely when nothing had gone wrong.

Root cause is the one already recorded twice in this ledger: **re-deriving a location that was
already known.** The backup filename now encodes the repo-relative path; a legacy basename backup
refuses rather than guessing, and says the backup is itself the pristine copy so a human can finish
by hand. Verified in both polarities.

## 6. Seam pattern (settled fleet-wide — one pattern, not two)

Default-argument injection; no test-only hooks on production types. A dependency becomes a parameter
whose default is the real thing, so existing call sites compile unchanged and tests pass a fake. For
a system framework, declare a small protocol over **only the surface actually used**, conform the
real type in one line, default the parameter to it. For time, take `now: Date = Date()`.

⚠️ `@testable import` elevates `internal` but **not** `private`. `ReaderView`'s logic is entirely in
`private` methods on a `View` struct — so the move is extracting the algorithm into an internal type,
not widening access.

## 7. Architecture audit findings (OBSERVED 2026-08-29, manager pass)

Found while reading for the seam design, not by a test. Each is a work item, not a note.

1. **CORPUS §4.6 is violated in five places.** The invariant says layout/timing is expressed with
   `.task(id:)`, never `DispatchQueue.main.asyncAfter`. Live violations:
   `ReaderView.swift:300, 303, 330` and `RSVPView.swift:334, 351` — flash/highlight animation
   timing. Every one of them is also an untestable race. Extracting them is both the invariant fix
   and the testability fix.
2. **The RSVP scrub gesture never resets `lastDragTime` in `.onEnded`** (`RSVPView.swift:318-322`
   resets `lastDragX`, `dragAccumulator`, `dragVelocity` but not the timestamp). So the first
   `.onChanged` of a *new* drag computes `deltaTime` as the idle interval since the previous drag
   ended, and derives `dragVelocity` from it. This is adjacent to roadmap **B4** and probably part of
   the same defect; the fix must be proved with a test that drives a *sequence* of samples **across a
   gesture boundary**, since a single-drag test cannot see it.
3. **`LibraryLayoutPreviews.swift` (140 lines) is `#if DEBUG`.** Coverage is measured on a Debug
   build, so `#if DEBUG` code sits in the denominator while never shipping. That is a real
   distortion in both directions and must be decided explicitly rather than discovered later —
   current stance: leave it in and cover it, since instantiating a preview is a legitimate
   smoke assertion.
4. **SwiftData is barely exercised.** `BookTests` constructs `Book` directly and never inserts it
   into a `ModelContext`; the only in-memory container in the repo is a private helper inside
   `OPDSLiveIntegrationTests`, i.e. inside the lane that does not run. Cascade delete of
   `Bookmark`/`Highlight`, relationship integrity, and the `tokenizedWords` legacy-migration path are
   all unproven. Promote that helper to a shared test utility.
5. **`WatchSyncService` is a `static let shared` singleton.** That is the reason its
   `WCSessionDelegate` half sits at 0% while the pure `WatchSyncLogic` half is well covered — there
   is no way to construct one under test. Seam it.

## 9. The bug the coverage number was hiding (CONFIRMED by reading, 2026-08-29)

`EPUBExtractor.swift` reads **71.96% covered** — comfortably the second-best-covered non-trivial
file in the app. That number is entirely the happy path. The chapter-assembly loop contains **four
independent silent-drop paths and not a single `else` branch**:

```swift
return spineIDs.compactMap { manifest[$0] }               // 1. idref not in manifest      -> gone
let fullPath = opfDir + decoded                            // 2. no path normalisation
if let fileData = entries[fullPath],                       // 3. ZIP lookup miss            -> gone
   let xhtml = String(data: fileData, encoding: .utf8) {   // 4. non-UTF8 chapter           -> gone
```

2 is the confirmed mechanism behind roadmap **B3**: a legal `href="../Text/ch1.xhtml"` becomes
`OEBPS/../Text/ch1.xhtml` by string concatenation and matches no ZIP entry key. 4 is notable because
`TextFileExtractor` already carries a UTF-8 → ISO Latin-1 → MacRoman fallback ladder — the project
has the idea and the EPUB path simply does not use it. A fifth: the manifest regexes require
double-quoted attributes, and single quotes are legal XML.

**Why this is the most serious finding so far, and why it is a *product* bug rather than a test
gap.** SpeedRead's entire position model is the word index (CORPUS §4.1). A chapter lost during
extraction does not merely truncate the book — it **silently shifts every saved position, bookmark
and highlight in that book**, and propagates the shift to the watch through the same index. The user
sees a shorter book and is told nothing.

**This is the case for the whole mandate, in one file.** 71.96% coverage, a real test suite, 150
passing tests, and a silent data-loss path in the single most important thing the app does. Coverage
found none of it; *reading the failure branches* found all of it. Any future push toward 100% that
does not ask "what happens on the else branch that isn't written" will reproduce exactly this.

## 10. Operator decisions (2026-08-29) — these are settled, do not re-litigate

1. **The gate is ATTRIBUTABLE, not HEADLINE.** Drive ATTRIBUTABLE and REACH to ~100%; report
   HEADLINE honestly alongside but do not gate on it. Rationale accepted: "covered" must mean *a
   test would fail if it broke*, and a literal 100% headline on a SwiftUI app is dominated at the
   margin by assertion-free renders of declarative markup — the laundering the mandate exists to
   prevent. **GHOST lines are reported and never count as progress.**
   → `Scripts/coverage.sh` must move its threshold from combined headline to attributable.
2. **CI: add a self-hosted `speedread-mac` runner** for `legitimate-apps/SpeedRead` — 5th per-repo
   runner on this Mac, alongside `orrery-mac`, `faceoff-mac`, `command-mac`, `ntfyng-mac`. Private
   repo, so self-hosted is safe. Must have `concurrency: cancel-in-progress`, per-job
   `timeout-minutes`, and a row in `~/.claude/STANDING-AUTOMATION.md` with an off-switch. Never
   GitHub-hosted macOS (10× multiplier).
3. **Release: quality now, ship on the operator's word.** 1.2 stays staged and ready; do not
   archive, submit, or touch version numbers. Note the release will have real substance whenever
   it is called — B4 (RSVP scrub jump) and B15 (swipe registers as tap) are both live defects on
   the shipping 1.1.

## 11. Leg 2 result — VERIFIED INDEPENDENTLY 2026-08-29

Reproduced by the manager with a bare `xcodebuild test` (no `-testPlan`, no `-only-testing`):
`environmentDescription: Hermetic`, **182 tests, 0 skipped, 0 failed**.

| | baseline | after leg 2 |
|---|---|---|
| HEADLINE | 17.77% (1486/8362) | **42.91%** (3700/8623) |
| ATTRIBUTABLE | 72.50% | **81.42%** (3282/4031) |
| REACH | 19.3% | **46.7%** — more than doubled |
| GHOST | 318 lines / 4 files | 418 lines / 5 files |

**The gain is attributable, not ghost** — that was the thing worth checking, and it held.
`ReaderView` 0% → 85.82%, `RSVPView` 0% → 86.39%, both new session types at 100%. The denominator
*grew* (8362 → 8623) rather than shrinking, so nothing was hidden.

**Red-first discipline is verifiable in history**, not just claimed: every `test(...) red` commit
precedes its `feat`/`fix` counterpart, and the red commits carry an intentionally inert production
scaffold whose comment says so. The B4 fix (`f063ad6`) is 5 insertions: `lastDragTime = nil` added
to the gesture reset, plus threshold classification for B15.

**My B4 hypothesis was right and the roadmap was wrong.** The roadmap blamed the `lastDragX` reset;
that reset is *required*, because `DragGesture.Value.translation` restarts at zero each gesture. The
real defect was the missing `lastDragTime` reset, which let a new drag inherit the previous
gesture's timestamp and compute ~1600 pt/s of phantom velocity — dropping effective resolution from
8 pt/word to 2.5 and jumping six words instead of two.

**Deviation accepted:** Sol declined roadmap I4 (split the RSVP tap zone into top/bottom halves),
arguing one recognizer distinguishes tap from scrub by distance threshold without making users learn
spatial zones or shrinking either action's surface. That is the better design and B15 is genuinely
fixed. I4 should be closed as "won't do", not left pending.

## 12. CLOSED — RSVP play/pause was unreachable by assistive technology (closed, re-audited 2026-09-01)

`RSVPView` has no accessible play/pause control. The only way to start or stop the stream is
tapping the word display, which is a bare `DragGesture(minimumDistance: 0)` (previously
`.onTapGesture` — equally invisible). VoiceOver, Voice Control, Switch Control and keyboard cannot
reach the **primary interaction of the app's flagship mode**. Not a regression from leg 2; a
pre-existing defect leg 2 walked past.

This sits directly against the *reasoning* behind CORPUS §4.5 ("tappable words are `Button`s —
Voice Control, focus and keyboard navigation depend on it"). The invariant is written for reader
words; the argument applies identically here. Roadmap I16–I19 already carry a11y work. Queue it.

✅ **Fixed and pinned, and this entry was stale for a while before anyone noticed.**
`RSVPPlaybackControl` is a real `Button` carrying `accessibilityLabel` / `accessibilityHint` /
`accessibilityIdentifier`, wired at `RSVPView.swift:233`, and named by
`ReadingViewRenderingTests`. The watch has its own equivalent in `WatchRSVPSurface`. The surviving
`DragGesture(minimumDistance: 0)` at `RSVPView.swift:310` is the *scrub* gesture — an additional
affordance beside the accessible control, not the only path to playback.

**A full sweep for the same defect class found no others**: the only remaining gesture-only
interactions in the app are `BrowseServerView`'s tap-to-dismiss-an-error-banner and the watch word
display, both of which sit beside a real control.

## 13. Leg 3 — EPUB silent chapter loss (Sol's report; manager verification pending)

Nine commits, red-first throughout, all five predicted drop paths reproduced then fixed. Sol found
**two more** en route that I had not predicted: an unsupported *declared* encoding silently returned
text as if decoding had worked, and a BOM-less UTF-16BE chapter garbled after the first decoder
implementation (recorded red in `7be39f3`, fixed in `77a4130`).

Structural upgrades beyond the brief:
- **Regex OPF parsing replaced with `XMLParser`.** The old manifest regexes were sensitive to quote
  style and attribute order; the container XML was likewise parsed by assuming `full-path="..."`.
- **Extraction now throws instead of returning a short book.** `DocumentImporter` calls the extractor
  *before* constructing or inserting a `Book`, so a partial book cannot be persisted. Both existing
  user-facing error surfaces (local import alert, OPDS download error) carry it.
- **Empty chapters are retained in spine order** rather than conditionally dropped, so a whitespace
  `stripHTML` result can no longer masquerade as a missing chapter.
- **ZIP now indexes from the Central Directory**, with the old local-header scan kept as the
  documented fallback for archives that genuinely lack one.

iOS 42.91% → **44.75%** (3978/8890), `EPUBExtractor.swift` 71.96% → **87.92%** (473/538), 198 tests,
0 skipped. **Reproduced independently by the manager** with a bare `xcodebuild test` — every figure
matched exactly, and attributable rose to **82.83%** (3560/4298).

**The assertion-audit tool earned its place immediately:** it flagged three new EPUB tests as
assertion-free because their assertions lived in a shared helper rather than in the named test. Sol
restructured them so each test owns its assertions. That is exactly the "looks covered, names
nothing" shape the harness exists to catch, caught on its first real outing.

**Outstanding:** `Scripts/coverage.sh` still gates on *combined headline* coverage. Per operator
decision §10.1 it must gate on **attributable**. Sol tripped over this — it invoked the script with
`42` meaning the iOS number and got a failure against the combined figure. Fix in the next leg.

**Housekeeping:** a `speedread-tests-2` DerivedData lease is still registered. Sol could not release
it because an unrelated `peer-ci` process has held the global `dd-lease` registry lock for
26+ minutes; `dd-lease list` still hangs as of 14:04. Correctly left alone rather than killed.

## 14. Crown direction — operator-reported bug, fixed red-first 2026-08-29

The operator reported that stepping through words with the Digital Crown moved through the book
backwards. Two candidate causes existed and they needed **opposite** fixes, so rather than guess I
put the discriminating question to them: does it go wrong on the very first turn from a fresh open
(direction inverted), or does it snap back to the position you opened at (a stale `crownValue`)?
They answered direction.

Fixed as `CrownSeek`, a named type holding the decision, with the view holding none of it. The
direction is a *product* decision — `digitalCrownRotation` does not state which physical rotation
its rising value corresponds to — so it belongs somewhere a test can pin it and a future change is
one line.

```
RED    aHigherCrownValueLandsEarlierInTheBook      2 issues
       oneDetentOfCrownTravelMovesExactlyOneWord   (a - b -> -1) == 1
       indexIsClampedInsideTheBook                 2 issues
GREEN  11/11 on watchOS 26.5, and again after the view was rewired
```

Commits `51cbaf6` (red) → `1596990` (fix) → `6292f3a` (wire the view).

### CLOSED — was "deliberately not patched", superseded by leg 5

`crownValue` used to be written **only** in `.onAppear`, so after playback the first detent snapped
the reader back to wherever they opened RSVP. Real, and *not* what the operator reported. It was
deliberately left alone because `browseWordIndex` in the three-marker design was going to handle it,
and patching it twice would have been churn.

✅ That design shipped in leg 5 and the deferral paid off: `crownValue` now follows the engine
(`WatchRSVPView.swift` writes it on `.onChange`, on load, on chapter browse and on restore), so the
snap-back is gone as a consequence of the model rather than as a spot fix.

## 15. Watch settings + position model — APPROVED AND SHIPPED (legs 5 + 8)

Operator decisions taken so far (architectural path, brainstorming skill):
- **Three markers in the one word-index coordinate space** — this does not bend CORPUS §4.1, which
  fixes the coordinate *system*, not the number of markers in it:
  `lastReadWordIndex` (reading; syncs; last-write-wins on timestamp) ·
  `browseWordIndex` (crown/chapter/scrub; **device-local, never syncs**) ·
  `furthestReadWordIndex` (syncs; **merges by max**, so clock skew and out-of-order delivery cannot
  corrupt it).
- **Commit rule:** reading commits, browsing does not. Press play, playback advancing, or closing
  after playing. Opening a book commits nothing.
- **Phone side prompts** — "Continue from Apple Watch?", dismissible, only when newer and materially
  different. Phone→watch still applies silently; a modal on a 44 mm screen is worse than the problem.
- **Chapter row hidden** when a book has no real chapters. No synthetic parts.
- **Sequencing:** sheet first (WPM + recall), chapters after — chapters need the extractor to
  preserve spine boundaries, a `Book`/`WatchBook` field, a sync-payload field, and a migration that
  must not shift a single word index or every saved position, bookmark and highlight breaks.

✅ **Approved by the operator** ("Go — design and rename both") and shipped. The rename is live:
`WatchSettingsView.swift:31` reads `Label("Back to where I was reading", …)`. Both operator-reported
watch items are closed and measured; nothing in this section is awaiting a decision.

## 16. Legs 4 and 5 — VERIFIED INDEPENDENTLY 2026-08-30

Leg 4 completed just before the 08-29 fleet reboot and **its report was lost with `/tmp`** — only
the commits survived (`0fcd21a..f200bb7`). It was verified from the code and a clean run rather than
from any claim, which is the posture that made the loss survivable. Leg 5 followed.

| | baseline | after leg 3 | after leg 5 |
|---|---|---|---|
| combined HEADLINE | 15.76% | 38.03% | **48.51%** (5596/11535) |
| combined ATTRIBUTABLE | — | — | **83.99%** (4763/5671) |
| iOS attributable | 72.50% | 82.83% | **85.42%** |
| **watch headline** | **0.00%** | 7.06% | **55.77%** (1281/2297) |
| tests | 150 (5 silent skips) | 216 | **276**, 0 assertion-free |

The watch number is the standing goal in CORPUS §5.1 finally becoming true: it went 0% → 7.06% by
*wiring a lane that had never run*, then 7.06% → 55.77% by actually testing the surface.

**The gate now measures what the project is held to** (operator decision §10.1): `Scripts/coverage.sh`
gates ATTRIBUTABLE and reports headline/attributable/reach plus the ghost list. It also fails a target
whose attributable lines are covered zero — the exact shape that hid the watch lane for months, where
"no coverage yet" and "your lane is not wired" were indistinguishable.

### What leg 5 built (the approved three-marker design, phase 1)

Each marker's merge rule is pinned by a test that **fails under either of the other two rules** —
that was an explicit requirement, because a `max`-merged marker that passes a last-write-wins test
pins nothing. The furthest-read test covers `local 80 / incoming 20 → 80` *and*
`local 20 / incoming 80 → 80`; last-arrival-wins fails the first, device-local fails the second.

**Browsing on the watch provably cannot alter the phone's reading position**, proven by asserting
that crown browsing publishes *no* `WCSession` application context at all — an absence, not an
argument. Sol additionally mutation-checked its own browse test by swapping local assignment for
`max` and quoting the failure.

**One product decision Sol made that the design had not specified**, correctly flagged as ASSUMED:
"materially different" for the Continue-from-Watch prompt is `max(5 words, 1% of the book)`. Isolated
in a pure predicate and pinned by tests, so it is a one-line change.

**One honest ASSUMED worth keeping visible:** no physical Digital Crown rotation was injected. That
the crown scrolls the settings `List` follows from using a native watchOS `List` plus an accessibility
tree reporting it scrollable — it is not an observed hardware input. Owed: a manager pass that
exercises it directly.

### Migration hazard — audited, contained

The two new `Book` fields default to `-1` sentinels for pre-existing stores, replaced with
`max(0, lastReadWordIndex)` by `ensurePositionMarkersInitialized()`. Every read of the markers in
the views and in `applyIncomingPosition` calls that first, and results are clamped to
`max(0, wordCount - 1)`.

✅ **CLOSED — re-audited 2026-09-01, and the ledger was stale.** This entry used to read "one spot
is safe by invariant rather than by construction: `continueFromWatch` reads `furthestReadWordIndex`
without migrating first… harden when next in that file." Both halves are now done and were done
before this audit, which is the point worth recording: **a written-down TODO outlives the work that
satisfies it, so re-read the code before re-reporting the gap.**

- Safe by CONSTRUCTION: the pre-migration read is `min(max(0, book.furthestReadWordIndex), lastValidIndex)`,
  so a `-1` sentinel is neutralised at the read rather than reasoned about; the mutating write happens
  after `ensurePositionMarkersInitialized()` (`WatchSyncService.swift:664`).
- Pinned by a TEST, not by the argument: `independentlyConstructedOfferIsClampedAndRepairsLegacyMarkersWhenAccepted`
  drives a book with `browseWordIndex = -1` and `furthestReadWordIndex = -1` straight through
  `continueFromWatch`. The non-local reasoning is no longer load-bearing — if someone deletes the
  clamp, a test goes red instead of a sentinel escaping into a saved position.

## 5j. A plan can be wired to a target and still be invoked by NOTHING (OBSERVED 2026-09-01)

**The find.** `UI.xctestplan` and `WatchUI.xctestplan` are both correctly wired to their targets and
enabled. **No automated lane runs either of them.** `Scripts/coverage.sh` invokes exactly two plans,
`Hermetic` and `WatchHermetic`, and CI's only test step is `Scripts/coverage.sh 82`. So
`SpeedReadUITests` and `SpeedReadWatch Watch AppUITests` could not fail a build.

**Why that matters more than it sounds.** `CrownDirectionUITests` is the test that closes the
operator's own reported crown-direction bug at the layer they actually experienced — the composition
of SwiftUI's `.digitalCrownRotation` binding with the inverted mapping. §5b was written to celebrate
wiring that target into a plan. It ran once, by hand, under a manager verification pass, and then
became permanently dormant. **The ledger recorded it as the moment the last ASSUMED link closed; in
fact the link closed for one afternoon and then silently reopened.**

**This is the same defect as §5b one level up, and that is the lesson.** §5b said target existence,
test existence and plan membership are three different facts. There is a fourth:

    target exists -> in a plan -> plan invoked by a lane -> lane actually executes tests

Every arrow is a place work can be real, correct, visible in reports, and inert. The 0.00% watch
lane broke arrow 2. This broke arrow 3. `Scripts/mutation-gate.py`'s `tests_ran()` exists because a
non-compiling mutation broke arrow 4 and scored as a KILL.

**Fixed structurally, not once.**
- `Scripts/lane-audit.py` walks all four arrows and fails the build on any break. It runs as a
  cheap gate in CI before any simulator starts. Exemptions are a dict with a written reason —
  `Integration` is exempt because it needs live OPDS credentials and cannot run unattended — because
  a silent skip would recreate exactly the blindness the script removes.
- **Positive control, OBSERVED:** with `Scripts/ui-lanes.sh` hidden, the audit fails and names `UI`
  and `WatchUI` specifically. The instrument demonstrably fires on the real historical bug rather
  than merely agreeing that today is fine.
- `Scripts/ui-lanes.sh` runs both UI plans as a second CI job, `needs: hermetic` so the two never
  race for the machine.

**The UI lanes deliberately do NOT feed the coverage number.** A UI test drives the whole app through
its host process, so every view it walks past records as covered with nothing asserting on it — the
GHOST shape the attributable gate exists to reject. Folding them into `coverage.sh` would have raised
the headline number by laundering, which is the one thing the mandate names outright. They report
pass/fail only.

**And the script does not contain the bug it was written to catch:** a lane that executes zero tests
exits 0 and reads green, so `run_lane` parses the executed-test count out of the log and fails the
lane at zero.

## 5k. The UI suite was mostly CAPTURE SCAFFOLDING, and the assertion gate could not see it (2026-09-01)

Before wiring the dormant UI plans into CI (§5j), the suites were read rather than assumed healthy.
**Six of the ten UI tests are not tests.** They assert that a screen appeared, then `Thread.sleep`
for an external screenshotter and return.

The clearest case is `WatchSyncUITests.testSendFirstBookToWatch`: it asserts the "Send to Watch"
button exists, taps it, sleeps six seconds, and ends. **It passes whether or not anything is ever
sent** — and it cannot work under XCUITest anyway, because XCUITest clones the simulator and the
clone has no paired watch, which is exactly why CLAUDE.md documents `--auto-send-first-book` as the
way to drive that path instead.

**`Scripts/assertion-audit.py` passed all six**, and was right to by its own rule: every one of them
*contains* `XCTAssert`. The assertions are about SETUP. Nothing is asserted about the behaviour the
test is named for. **Counting assertions cannot distinguish "asserted the outcome" from "asserted
the preconditions and then waited."**

**The mechanical signature is exact: a sleep with no assertion after it.** The audit now checks for
it, with a named-exemption dict for the same reason `lane-audit.py` has one. Run against the repo it
finds 6 of 331 tests, and it separates the two remedies correctly:

- `testLibrarySupportsPortraitAndLandscape` is a REAL test (it asserts the nav bar in both
  orientations) carrying a vestigial trailing sleep. Remedy: delete the sleep, keep the test.
- The other five are holders with nothing behind them. Remedy: delete them. Nothing references them —
  no script, no workflow, no doc — and the sanctioned replacement is the documented `--auto-*` launch
  arguments, which capture a screen without cloning a simulator.

**Why this mattered before the CI change and not after.** Wiring the UI plans in would have added
~45 s of pure sleep per run and, worse, would have made a vacuous green look like watch-sync
protection. A dormant bad test is harmless; a *running* bad test is a claim.

## 5l. Cross-project CI contention is real and unmanaged (OBSERVED 2026-09-01)

Leg 11 stalled mid-flight waiting for the machine, and the two `xcodebuild` processes it was waiting
on belonged to **another app's CI on the `peer-mac` runner** — a different project entirely.

Six per-repo self-hosted runners live on this Mac and each will run a job whenever its repo is
pushed. Nothing coordinates them, so the fleet can put up to six concurrent Xcode builds on a machine
whose measured ceiling is about two. Swap was already at 3.9G of 5.1G with just those two running.

Sol waiting rather than starting a third build was the correct behaviour and is why leg 11 was not a
fourth SIGKILL. SpeedRead's own two jobs are serialised (`needs: hermetic`); across projects there is
no such guard. **Flagged, deliberately not fixed here** — runner concurrency policy is fleet-level
standing automation, not this project's to change unilaterally.

## 5m. `SpineColor.swift` — a diverged copy, found by a peer's audit method (OBSERVED 2026-09-01)

The peer-project TDD session diffed every filename present in both its app and watch trees and found
three real defects hiding in the residue of earlier de-duplication passes. Run here, the same audit
took seconds and hit on the first try.

**8 filenames appear in both trees. 7 are symlinks to a single file. `SpineColor.swift` is a real
copy, and it has diverged.**

- Palette values and the hash function are IDENTICAL, so classic-theme colours agree today.
- iOS `BookSpineView.swift:28` calls a themed overload,
  `SpineColor.color(for:from: themeManager.currentTheme.spineColors)`. **That overload does not
  exist in the watch copy.** `WatchLibraryView` and `WatchBookDetailView` call the plain
  `color(for:)`, which is hard-wired to the classic palette.
- Consequence: **whenever a non-classic shelf theme is selected, the same book is a different colour
  on phone and watch.** Cosmetic, but it lands squarely against standing goal 1 — the watch is
  first-class and must not be "a demo that rots between releases."
- `SpineColorTests` exists only in `SpeedReadTests`. The watch's copy is named by no test in the
  watch lane, so the drift had no way of being noticed.

**Why the method works, stated generally: the residue of a de-duplication pass is a list of files
someone judged unshareable, and that judgement answered "COULD these be shared?" — never "have
these two copies DIVERGED in ways that matter?"** The filename collision is the entire signal; no
comment or annotation is needed to find it.

**There is a FIFTH arrow, and the peer named it from this case.** §5j's chain was
target -> plan -> lane -> executed. `SpineColorTests` clears all four — it exists, it is in
`Hermetic`, that plan is in a lane, and the lane runs it — and it still could not have caught this,
because **it is pointed at the iOS copy and the bug is in the watch copy.** A test can exist, run,
and simply not be aimed at the code that ships on the platform that is wrong.

That arrow is now a PROPERTY rather than an audit: `Scripts/shared-source-audit.py` fails when a
filename exists in both trees as two real files, **even when they are byte-identical today**, because
a copy that is identical today is a copy that drifts tomorrow. Controls run in both polarities: it
passes on a symlinked pair and fails on a byte-identical real copy. The peer cannot do this in their
repo (23 shared pairs, zero symlinks) and has to keep diffing; here 7 of 8 are already symlinks, so
the gate just keeps true a thing that is nearly true already. **A diff is a control someone must
remember to re-run; a symlink is a property.**

Scoped for leg 12 as a divergence fix, not a feature: collapse to one shared source and pin the
watch's behaviour in the watch lane. Theme *syncing* is deliberately excluded — the watch has no
access to the phone's `selectedThemeId`, so matching colours needs a new synced field, which is a
product decision the operator has not been asked.

## 5n. Two corrections to entries written earlier in this same session

**The capture-holder detector's yield is project-shaped, and I nearly generalised it.** 6 of 331
here; the peer ran the identical check and reported **1 of 1,131**, then corrected their own
denominator unprompted: the detector only scans test bodies, and the idiom only exists in a UI
target, so the honest figure is **0 of 10 UI tests**. Their single hit was in another target and was
a deliberate opt-in `XCTSkip` probe rather than a test pretending to assert. So the honest claim is
"high yield wherever UI screenshot scaffolding exists, ~0 otherwise" — it keys on the
assert-then-sleep-for-an-external-screenshotter idiom, which is a property of having a capture
pipeline at all. **Recorded with its scope rather than as a universal smell**, the same discipline
§5d's headline-nondeterminism claim needed.

**My CI-contention attribution was half wrong.** §5l said both blocking `xcodebuild` processes
belonged to another app's CI. The dispatcher measured it: one was peer-mac CI, the other was a peer
session's *interactive* Sol leg. I had traced ONE parent to a runner temp script and extended the
conclusion to both, when tracing the second was one command away — and I had in fact printed its
parent (`timeout 2700 xcodebuild …`), which is not a runner script and said so plainly.

The conclusion in §5l survives unchanged (both slots were another app's work; six uncoordinated runners
on a two-build machine), but the reasoning that reached it was the session's recurring failure again:
**a plausible explanation arriving before a check that was already in hand.** That is now four
instances in two days — the coverage "drop", the process count, the thread corruption, and this. The
common repair is the same one §5d needed: ask what else in the record would have had to be true, and
look, because the record is usually already on screen.

## 5o. The gate's own stall — a fix I found, recorded, and never applied where it mattered (2026-09-01)

`Scripts/mutation-gate.py` sets `-collect-test-diagnostics never` and carries a comment explaining
why. **`Scripts/coverage.sh` — the script CI actually runs on every push — never set it.**

I discovered that flag *in this project*, wrote it into one script, told a peer session about it,
and left the gate that runs on every push exposed to it. The peer then lost a delegate leg to
exactly that stall the same afternoon, which is what prompted the check.

Why it matters more here than in a normal lane: **`coverage.sh` is a GATE, so going red is its job**,
not an edge case. It runs two lanes, so a bad push can buy up to 20 minutes of
`simctl diagnose --timeout=600` against a 40-minute job timeout — and the real harm is not the
wall-clock, it is that **a clear test failure presents as an ambiguous timeout.**

⚠️ **Not a universal rule, and the peer was right to push back on the version of this that reads as
one.** They keep the collector ON in CI deliberately, on the sound grounds that a failure you cannot
reproduce locally is exactly when you want diagnostics. What decides it differently here is narrow
and checkable: **this workflow has no `upload-artifact` step, so nothing ever consumes the output.**
The collector writes a sysdiagnose into the runner's work dir that no human will open. If we ever
want CI diagnostics the fix is to upload them and pay the cost on purpose — not to re-enable a
collector nobody reads. Their position gets stronger the moment they add upload; mine would flip.

### The better answer is a SPLIT, and it exposed a second half of the bug (revised 2026-09-01)

The peer went and checked their own justification instead of defending it, found their runner wipes
`RUNNER_TEMP` between jobs with zero diagnostic bundles anywhere under `_work`, and withdrew it. Then
they proposed the answer that is better than either of ours, and it applies here unchanged:

**`never` for the sysdiagnose, PLUS keep the `.xcresult` on failure.**

Because the framing "diagnostics or no diagnostics" hid the real defect: `coverage.sh` writes
`-resultBundlePath` into `work_dir`, and the `trap cleanup EXIT` deletes `work_dir` **on failure
exactly as on success**. So a red run was paying up to 600s for the expensive artefact nobody reads
and discarding the cheap one that names the failing test. Both halves wrong, in opposite directions.

`preserve_failure_evidence` now copies the bundle and the log to a durable directory on a failing
lane. It never falls back to the boot volume — this Mac has repeatedly hit "disk full" and
`.xcresult` bundles run to tens of megabytes — so no external drive means a warning and no artefact,
which is a worse debugging experience and a better failure mode. And it can never itself fail the
run: the lane already failed, and that verdict is the thing that matters. Controls run in both
polarities.

**The transferable failure is about a note's TRIGGER, not its content.** The peer named it precisely:
they had filed the tip under "local red runs", then had a delegate drive `xcodebuild` by hand to
prove a CI lane could fail — the most local red run there is, deliberately red — and did not fire
the note, because they had categorised the instance by its PURPOSE ("verifying CI") rather than by
its MECHANISM. Mine failed the same way: I filed it under "the mutation gate stalls", not under
"anything that runs a suite expecting red."

## 5p. UI lanes VERIFIED, and the preservation step that would have kept nothing (2026-09-01)

**OBSERVED, first automated run of either UI plan in this project's history:**

```
Running iOS UI lane...
  iOS UI lane: 4 tests executed
Running watchOS UI lane...
  watchOS UI lane: 1 tests executed
PASS: both UI lanes executed and succeeded
```

That watchOS 1 is `CrownDirectionUITests` — the operator's own reported bug, now covered by a test
that a build can actually fail on. §5j's gap is closed by measurement, not by wiring.

It also validates the executed-count parser against real `xcodebuild` output. That parser is the
whole reason the script can tell "passed" from "ran nothing", and its first version returned **1 for
every log** because awk evaluates a `/regex/` literal passed as a function argument as a match
against `$0`. Caught by a control asserting the expected value 42, not merely that a number came out.

### The `if [ -e ]` with no `else` — a preservation step that cannot fail loudly

`preserve_failure_evidence` originally copied with `[[ -e "$src" ]] && cp …`. A peer session found
the same shape in their own workflow and stated the rule better than I had it:

> **A guard of the form `if <thing exists>` needs an `else` when it protects an ARTEFACT rather than
> an ACTION.** For an action, skipping silently is usually right. For a preservation step, the skip
> IS the failure, so silence is the bug.

Without the `else`, "there was genuinely nothing to preserve" and "I built the wrong path" produce
identical output — none. Theirs had been pointing at `unitFILE.xcresult` from a chained
`.replace()`, so it would have preserved nothing forever while reporting success. **A backup nobody
has ever restored from is not a backup.** Both scripts now warn on a missing expected artefact and
print the destination on success; controls run in both polarities.

### Two instrument lessons banked from the same exchange

- **Merging stderr into a value you are about to parse manufactures the symptom you then
  investigate.** My `dd-lease` probe used `2>&1`, showed diagnostics mixed into the path, and nearly
  produced a "bug in `coverage.sh`" that does not exist. Separated: diagnostics on stderr, value
  alone on stdout. Same family as a verification sweep at 2s intervals generating four of its own
  "dead links" — the instrument creates the reading and is then believed.
- **A wrapper's status is a fact about the wrapper.** A background-task harness reporting `killed`,
  `tee`'s exit code standing in for `xcodebuild`'s, a GitHub run's aggregate conclusion standing in
  for its jobs' (a run with one cancelled and one FAILED job rolls up to `cancelled` — `gh run view
  --json jobs` recovers it). **If CI checking here ever reads a run conclusion, read the jobs.**
  Banked as `[[reference-read-the-something-else-not-the-wrapper]]`.

**And the propagation failure, which is the one I keep making.** `ui-lanes.sh` wrote its lane logs
into a `mktemp` dir deleted by the EXIT trap — the identical evidence-destroying defect fixed in
`coverage.sh` an hour earlier, in a file I wrote *afterwards*. Third instance today. The peer's read
of it is sharper than mine: **their version was a typo; mine is a design that is correct in the
happy path and destroys exactly what you need in the unhappy one.** Those are harder to see, because
nothing about the code looks wrong until the moment it matters.

## 5q. ATTRIBUTABLE coverage is FILE-granular, so it punishes extracting logic (2026-09-01)

After leg 11, the gate went **RED**: combined attributable fell 83.94% -> 74.18% against a floor of
82%. Leg 11 added tests and removed a crash. The number got worse because the work was done well.

**Measured, not inferred** — the discriminating figures are the per-file rows:

```
logic in its OWN file        OPDSBrowseLogic.swift       39/40     97.50%
                             OPDSServerFormLogic.swift   39/39    100.00%

logic INSIDE the view file   BrowseServerView.swift      46/798     5.76%
                             ServerEditView.swift        73/481    15.18%
                             ServerListView.swift       160/241    66.39%
```

798 + 481 = **1,279**, and the iOS attributable denominator grew by exactly **1,287** (6,383 ->
7,670). The cause is fully accounted for, which is the standard §5d had to meet: **a test naming
`BrowseServerLogic` marks `BrowseServerView.swift` as "named", because the logic type was declared
inside the view file — so 798 lines of SwiftUI body markup entered the attributable denominator with
119 of them covered.**

⚠️ **This is a property of the metric the operator chose to gate on, and it is worth stating
plainly: attributable coverage is only meaningful if file boundaries separate tested logic from
untested view markup.** Co-locate them and the metric reports *worse* the more logic you extract,
which is exactly backwards — it penalises the refactor it exists to encourage. It is not an argument
against gating attributable; it is a precondition for it, and the precondition was previously being
met by accident.

**Fix: relocation, not a threshold change.** `BrowseServerLogic`, `ServerEditLogic` and
`ServerListLogic` moved into their own files, restoring the pattern `OPDSBrowseLogic` and
`OPDSServerFormLogic` already followed. Each new file's header carries **its own** measured figure —
the first generated version applied one file's numbers to all three, which would have put a false
66.39%-as-5.76% claim into the source. A wrong comment is worse than no comment: it disables the
check that would have caught it.

**I did this relocation myself rather than dispatching it**, against the standing routing rule, and
the reason is narrow: it is cut-and-paste with zero design content, the destination pattern was
already established by two existing files, and it was blocking a verified commit. Recording the
deviation rather than leaving it implicit.

**What must NOT happen here is lowering the floor.** The gate did its job: it went red on a real
structural problem that no test failure would have shown. Ratcheting down to accommodate it would
have converted a working instrument into a rubber stamp.

## 5i. Post-reboot hydration + leg 11 (2026-09-01)

**Fleet reboot, second compaction boundary, full transcript mined — nothing lost.** All five record
shapes checked by FIELD, not string: 57 `type:"user"`, 41 `queued_command`, 172 `queue-operation`,
0 `goal_status`, and 4 `AskUserQuestion` tool_use ids each paired to an answered `tool_result`. The
only genuine typed operator input hiding in the queue shapes was already on the board (the two watch
requests and "go go go all"). Recording the negative because a clean hydration result is the one most
likely to go unreported.

**One relayed order was stale and was not executed.** The dispatcher's post-compaction brief listed
"the PAT was APPROVED — mint it, secret put it, register the self-hosted runner, uncomment the 3
trigger lines" as open. All four were already done, and none had ever needed a PAT. Two commands
settled it. Banked as `[[reference-a-relayed-approval-is-not-a-requirement]]`: **a relay carries
authority over a decision, not over a fact.**

**CI health was verified without touching `gh`.** `~/actions-runner-speedread/_diag/Runner_*.log`
ends in `Listening for Jobs` (reconnected 18:34:53Z) and the newest `Worker_*.log` carries
`StepsRunner] Result: true` per step. This mattered beyond convenience — `gh`'s active account had
flipped to another account, so an API read would have crossed identities against a private LLC repo.
Banked as `[[reference-verify-ci-from-runner-logs]]`.

**Machine state at dispatch (OBSERVED):** swap 587M of 1024M (it was 14.0G of 14.3G when three legs
were SIGKILLed), 52% free, 4 CoreSimulator processes, X8 mounted with 124Gi. All `sim-lease` and
`dd-lease` leases released by the reboot. This is what a safe dispatch window looks like; the
contrast with the killed legs is the calibration.

**Leg 11 dispatched** against the three remaining unreached iOS view files — `BrowseServerView` (312),
`ServerEditView` (232), `RemoteBookDetailView` (201) — plus the mutation proposals owed from legs 9
and 10, both of which died before delivering them. Scoped commit-per-deliverable again, because that
instruction is the only reason leg 10 landed five commits despite being killed. The brief names one
hazard (`server.baseURL!` force-unwrapped twice in `BrowseServerView`) **explicitly as unverified by
me**, with an instruction not to treat my framing as the answer — the correction from §5e.

