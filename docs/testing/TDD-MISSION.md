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

## 5r. Leg 12 — the watch trio, network isolation, and SpineColor closed (VERIFIED BY MANAGER 2026-09-01)

Seven commits, every one a red-then-green pair, pushed at `87ac743`. Verified independently before
reading Sol's report:

- **Watch view trio.** `WatchSettingsLogic`, `WatchRSVPViewLogic` and `WatchAppLaunchLogic` extracted
  into their own files (CORPUS §4.8 was already in the brief, so the new logic did not repeat leg
  11's co-location mistake). **Watch files named by no test: 3 -> 1** — only
  `SpeedReadWatchApp.swift` (32 lines) remains.
- **`SpineColor.swift` is now a symlink** into `SpeedRead/Theme/`. `Scripts/shared-source-audit.py`
  passes 8 of 8 single-source, so it is wired into CI with an **empty exemption dict** — the
  condition I had set for wiring it at all.
- **Network isolation is a harness property, not a convention.** `HermeticNetworkGuardURLProtocol`
  `fatalError`s on any escaping request. Its positive control lives in its **own test plan**, which
  is the right shape: a control that must FAIL by design can never sit in a lane whose job is green.
- **Mutation proposals delivered** (six), `Scripts/mutations.json` untouched and the gate not run —
  the boundary held, so replaying a delegate's verdicts through my resume ledger stays impossible.
  Two proposals carry honest self-criticism (an encoding mutant that may algebraically collapse, a
  clock mutant that preserves relative ordering), and one deliberately re-introduces leg 9's
  `/opds/opds/search` duplication to test whether that fix is actually pinned.
- Sol **discarded its own green result** when a selector-shaped invocation reported `TEST SUCCEEDED`
  while executing zero tests, and re-ran the full target. That is §5j's lesson applied by the
  delegate without being told.

## 5s. My own gate had a self-referential hole, and a control that should have failed did not

Tightening `lane-audit.py` exposed two defects in it, both found because a **control failed to
fire** rather than because anything looked wrong:

1. It read every file under `Scripts/`, so *a plan name appearing anywhere* counted as *a lane runs
   this plan*. `NetworkIsolationPositiveControl` is named only by a script no workflow invokes — so
   it passed the audit while being exactly as dormant as the UI plans had been. **A script nobody
   runs is not a lane.** Only workflows and the scripts those workflows actually invoke count now.
2. **`lane-audit.py` lives in `Scripts/` and IS invoked by the workflow, so its own `EXEMPT_PLANS`
   dict counted as naming a plan — the exemption mechanism silently satisfied the check it exists to
   guard.** It excluded itself by FILENAME, which stopped working the instant a control ran a copy
   under a different name; that control then passed when it should have failed. Now self-identified
   by a content marker, because an identity you can state outright should never be re-derived.

All three controls re-run and firing: hide `ui-lanes.sh` -> names `UI`/`WatchUI`; drop the
positive-control exemption -> names it; add an exemption for a plan that does not exist -> names that.

## 5t. A zero has TWO failure modes, and the second one has no tell

From the peer session, and it sent me back to a claim I had already reported:

    "the code ignores this setting"   -> 0 references
    "the feature does not exist"      -> ALSO 0 references

**A zero tells you the intersection is empty, never which of the two sets was.** Their `grep -c
hapticsDisabled` returned an entirely ACCURATE 0 — and the inference was wrong, because every haptic
call in the file was commented out. The correct fix (make the feature work at all) is different work
from the one the finding named (restore parity).

⚠️ **And a contrast reads as stronger evidence than a bare zero while establishing strictly less.**
"iOS 9, watch 0" invites belief; a lone 0 invites "is my filter right?". The positive denominator
looks like a control and only actually proves the two inputs differ.

**Applied here immediately.** I had told the operator the `baseURL!` crash class was "contained",
on a grep whose pattern missed `try!` and `as!` entirely. Re-run with a pattern covering all three
forms: exactly one force-unwrap in production, a compile-time-constant UUID literal in a file a test
now names. The claim holds — but it held by luck of pattern coverage, and the zero alone could not
have told me which.

## 5u. Mutation gate on the leg 9-11 logic: the INVALID guard caught its first real one (2026-09-01)

Six proposals from Sol, selected and run by the manager — `Scripts/mutations.json` untouched, so no
delegate verdict was replayed through the resume ledger.

```
4 KILLED · 1 SURVIVED · 1 INVALID · 2 unexpected
```

**The KILLs that matter.** Re-introducing leg 9's `/opds/opds/search` duplication makes the suite
fail, so that real bug's fix is genuinely pinned rather than merely covered. Both surviving
default-argument mutants behaved: swapping the production credential store for `{ _ in nil }` was
killed, which is the historically weakest spot in this suite finally holding.

**The SURVIVOR is a real gap, and Sol predicted it in its own review note before the run.**
`urlPathAllowed -> urlQueryAllowed` in the search-encoding path survived because the fixture contains
no character on which the two sets differ, so both branches encode identically and the assertion
cannot see the change. Classified **real gap, not equivalent**, and now CLOSED.

The discriminating character was MEASURED rather than assumed (`?` -> `%3F` under `.urlPathAllowed`,
literal `?` under `.urlQueryAllowed`; `:` also differs). `searchEncodesWithThePathCharacterSetNotTheQueryOne`
pins it, and re-running the mutation against the new suite gives **KILLED**. The evidence is the
part worth keeping:

```
✔ searchActionTrimsEncodesAndPrefersAdvertisedTemplate()  PASSED under the mutant
✘ searchEncodesWithThePathCharacterSetNotTheQueryOne()    FAILED under the mutant
      got  .../who%20goes%20there?      expected  .../who%20goes%20there%3F
```

Two tests over the same code path, one blind and one discriminating, with the blind one having sat
there looking like coverage. **The old fixture used a space, which BOTH sets render `%20`** — so it
executed the line and asserted nothing about the decision on it. That is the difference between
coverage and pinning, in one diff.

A delegate predicting its own weak spot and being right is a better signal than a clean sweep would
have been. All six are now in `Scripts/mutations.json` (22 -> 28), every one measured KILLED.

**The INVALID is the important one.** `generatedTag: String = UUID().uuidString -> ""` compiles
perfectly well, so the mutation was not at fault. The log says:

```
Early unexpected exit, operation never finished bootstrapping - no restart will be attempted.
(Underlying Error: Test crashed with signal kill before establishing connection.)
```

**The test runner was killed by machine pressure while CI ran concurrently.** `xcodebuild` exited
non-zero, which at the exit-code level is **indistinguishable from a failing test** — so without
`tests_ran()` this would have scored KILLED and falsely certified that default argument as pinned.
That guard was added earlier today from reasoning alone; this is the first time it has caught a real
one, and it caught a false KILL rather than a false survivor, which is the dangerous direction.

⚠️ **A correction I made mid-investigation, because it is the day's recurring failure again.** I
stated the gate deletes its per-mutation logs and called it a fourth instance of the
evidence-destroying pattern. **False.** The gate writes to `$SCRATCH` (default `/tmp`) and keeps
them; my `find` searched `$TMPDIR`, which macOS points at `/var/folders/...`. The evidence was on
disk the whole time and the tool was fine. Same shape as every other one today: a plausible story
arrived before a check that was one command away.

## 5v. CI went red and it was MY fault, not the code's — and the preservation step paid for itself

The `UI lanes` job failed in CI at 20:23:21Z. Two tests in `ReaderTapToRSVPUITests`:
`Lost connection to the application` and `unexpected termination of com.legitimateapps.SpeedRead`.

**The evidence existed only because `preserve_failure_evidence` had been committed twenty minutes
earlier.** Without it the lane log lived in a `mktemp` dir the cleanup trap deletes, so a red CI job
would have left a failure with no readable cause. It kept `UI.log` and `UI.xcresult` on the external
volume, and they named both failing tests and the exact failure mode. That step went in on a peer's
argument, and I would have called it noise a day earlier.

**Diagnosis, with the checks that separated the readings:**

| hypothesis | check | result |
|---|---|---|
| a code change crashed the app | crash reports in the 20:19-20:23 window | **none** |
| the only crash today is unrelated | read it | 16:09, `HermeticNetworkGuard` -> `fatalError` — leg 12's positive control firing **by design** |
| the app was KILLED, not crashed | `Lost connection` + `unexpected termination` with no `.ips` | consistent |
| **I caused it** | CI's UI job 20:19-20:23 vs my isolated mutation-gate re-runs | **same window** |

Confirmed by the discriminating test rather than by the story: **the same commit passes both UI
lanes on a quiet machine** (4 iOS, 1 watch, OBSERVED). So the failure was contention, and the
contention was mine.

⚠️ **My own build-ceiling rule permitted this and was still wrong.** "Proceed when fewer than two
xcodebuild processes are running" let me start a simulator-booting mutation gate while CI held the
other slot — putting the machine *at* the ceiling during **UI tests, which are the heaviest case
there is** and the one where the app under test is a separate process that can simply be killed.
The INVALID mutant an hour earlier had the identical signature (`Test crashed with signal kill
before establishing connection`). Same cause, twice, an hour apart, and I did not connect them
until CI made it expensive.

**Revised rule: do not run local simulator work while CI is running at all.** CI is not one of two
slots to fill; it is the machine being busy.

**What was NOT done, deliberately:** no retry flag, no `-retry-tests-on-failure`. The lane failed
for a real reason and retries would convert a machine-pressure signal into silence. The fleet-level
fix (six uncoordinated runners on a two-build machine) is with the dispatcher and the operator.

**One real latent defect surfaced by reading the log**, separate from the cause:
`LibraryAdaptiveLayoutUITests` set `XCUIDevice.orientation = .landscapeLeft` and never restored it.
Orientation is process-wide and survives the test, so the next class started in landscape — the CI
log shows `Interface orientation changed to Landscape Right` during a later teardown. The trailing
`Thread.sleep` I removed (it was what made the test a capture holder) had been masking it. Fixed in
`tearDown`, where restoring state belongs.

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


## 5w. The control I built for the wrong lane, and a peer's broken probe that found it (2026-09-03)

A peer session set out to measure whether coverage figures are stable across two runs of the same
binary. Careful, symmetric design: same warm DerivedData, same leased simulator, same flags in both
arms, so the only variable was "run it twice". **Both runs executed zero tests** — 378s in
`IDETestOperationsObserver`, then "the test runner hung before establishing connection", exit 65.
`sample(1)` showed the main thread recursing in `-[DVTFilePath _locked_tentativelyInvalidate…]`
under `os_unfair_lock_lock`, with a 4.6 GB / 68,366-file DerivedData tree 56.8 hours old.

> **RETRACTED 2026-09-04, and I should have marked it ASSUMED when I wrote it.** The stack was
> OBSERVED; the *cause* was not. The peer's v2 ran on a FRESH tree (`dd_files_at_start=0`), an
> ephemeral simulator and a passing capacity gate, and **hung anyway** — 0 tests in ~540s. The
> DerivedData-size mechanism is refuted by their own next experiment.
>
> Worse, the fact that made it persuasive was false. They told me twice that the same SHA "passed
> the unit lane in CI on this machine 20 minutes earlier". `gh run list --json createdAt` says
> 2026-09-01T21:19:06Z — **2 days 7 hours earlier**, not 20 minutes. They read the run for its
> conclusion and never looked at its timestamp, taking "most recent run" for "recent run". The
> load-bearing contrast — green in CI and hung locally on the same host the same day, therefore
> neither the code nor the machine — never existed.
>
> I copied it into this ledger as established because it arrived with a `sample(1)` stack attached,
> and a real observation next to a claim lends it credibility it has not earned. That is exactly
> `[[reference-evidence-class-in-the-sentence]]`, and the discipline it prescribes — write the
> evidence class into the claim — is the thing that would have caught it. What survives: the
> DVTFilePath stack, the substrate-vs-known-good-recipe design error, and the executed-count
> catch. What does not: any claim that the machine was exonerated, or that tree size was the cause.

Their diagnosis of their own design error is the transferable part, and I am recording it in their
words: *symmetry between the two samples bought nothing once both sat on a substrate that could not
run tests at all.* Their CI ran the same SHA green twenty minutes earlier with a capacity gate, an
ephemeral simulator, per-run DerivedData and a CoreSimulator preflight. The probe had none of them.
**Replicate the known-good recipe; vary only the thing under test.**

### The half that landed on this project

Their second point: *a null result and a broken run are indistinguishable from a diff of the
outputs.* Two empty coverage reports diff clean, and "identical — the measurement is deterministic"
is exactly what that looks like.

So I checked whether my own gate could do the same thing, and it could — differently, and worse
than I would have guessed:

| | behaviour on a zero-test run |
|---|---|
| `Scripts/ui-lanes.sh` | asserts executed>0, names it: "executed 0 tests — the plan ran nothing" |
| `Scripts/coverage.sh` (**the gate CI runs**) | no such control |

`coverage.sh` does fail closed — `assert_attributable_lane_ran` catches covered==0 while
executable>0. But it fails saying **"combined attributable coverage is below 82%"**, which is the
wrong diagnosis. It sends the next person hunting a regression that does not exist.

**I had already built the right control, after the awk fail-open in §5p, and applied it only to the
lane that does not gate CI.** That is the same shape as §5o: a fix found, recorded, and not applied
where it mattered. Twice now, so it is a pattern rather than an incident — when a control is worth
building, the next question is *which other surfaces have this hole*, asked immediately, not later.

### What was built

- `Scripts/lib/executed-tests.awk` — the parser, now ONE copy. Folding it into `coverage.sh` would
  have created a second, and two copies of a parser drift. `shared-source-audit.py` enforces exactly
  this for Swift and does not watch `Scripts/`, which is how it nearly happened here.
- Both lanes now assert executed>0 and name the real failure.
- `Scripts/executed-tests-control.sh` — 10 fixture checks asserting **expected counts**, wired as a
  fourth CI honesty gate. Standing, not something a human remembers to run.

**The control was verified by breaking the parser.** Reintroducing the exact regex-literal bug made
6 of 10 checks fail, every one returning 1. The 4 that still passed were the empty log and the
no-test-summary logs — **a control built only from those would have certified the broken parser.**
The discriminating checks are the ones asserting a specific number, never a property. That is the
difference between a control and a formality.

### And then the control certified a parser that could not read this project's own logs

Thirty minutes after writing the above, while looking for a real log to check the *watchOS* format
against, I found this in `docs/testing/COVERAGE-BASELINE.md`:

```text
✔ Test run with 144 tests in 20 suites passed after 0.776 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.005 seconds.
```

**The parser returned 0 for that line.** My Swift Testing pattern was `[0-9]+ tests? (passed|failed)`
— written from memory, matching `"351 tests passed"`. This project emits `"144 tests in 20 suites
passed"`, where `tests` and `passed` are five words apart. So the new assertion in `coverage.sh`
would have failed **every healthy hermetic run** with "exited 0 but executed 0 tests".

**The control did not catch it, because the control's fixtures were invented too.** I wrote
`'✔ Test run with 351 tests passed after 12.345 seconds.'` as the fixture — the same wrong format,
from the same wrong memory. Parser and control agreed perfectly and were both wrong.

> A control whose ground truth is authored rather than sampled tests only that the author was
> self-consistent. It is not evidence about the system. **Fixtures must be pulled from real captured
> output** — and this repo had four such logs sitting in `docs/testing/` and on the X8 the whole time.

This is worse than the bugs it was built to catch, because it wears their defeat as a credential:
I had just demonstrated the control firing on a broken parser, published that as proof, and the
demonstration was sound *within* the fabricated world both artefacts shared.

Fixed by rebuilding every fixture verbatim from real logs (`COVERAGE-BASELINE.md`,
`READING-TDD-EVIDENCE.md`, and the archived iOS UI lane log on the X8), adding the
`[0-9]+ tests? in [0-9]+ suites?` pattern, and re-verifying against both bugs:

| injected bug | caught? | how it presented |
|---|---|---|
| missing `in N suites` pattern (mine) | yes, 4 checks | three returned **0**; one returned **40** instead of 144 |
| regex literals as function args (§5p's) | yes, 9 checks | every one returned **1** |

The 40 is the one to remember: a plausible non-zero, from a log that *did* contain other test
counts. A control asserting "a number came out" passes it. Only the expected count catches it.

**Caught by luck of sequencing, not by design.** Sol's leg was mid-build against this very script;
`awk -f` re-reads the file per invocation, so fixing the `.awk` alone (never the running
`coverage.sh`, which bash reads incrementally) took effect before the lane finished. Had I looked
for the watch format ten minutes later, I would have reported a healthy leg as a broken one.

## 5x. Leg 13 — two concepts, four implementations, and a delete that shifts under itself

Roadmap B16 was filed as "duplicated bookmark/highlight lists". What is actually there is worse:

| view | surface | ordering | delete | tested behaviour |
|---|---|---|---|---|
| `BookmarkListView` | RSVP | `wordIndex` | yes | none — named by no test |
| `ReaderBookmarkPicker` | reader | `wordIndex` | **no** | pixel-signature smoke only |
| `HighlightListView` | RSVP | `startWordIndex` | yes | none — named by no test |
| `ReaderHighlightPicker` | reader | `startWordIndex` | **no** | pixel-signature smoke only |

The behaviour has already diverged — you can delete an annotation from RSVP but not from the
reader — which is what `[[reference-shared-copies-diverge-where-dedup-gave-up]]` predicts. The only
assertions on the reader pair were `#expect(signatures.count > 2)`: they catch a crash and nothing else.

**A latent bug fell out of reading them side by side — and my first statement of it was wrong.**
Both RSVP lists delete like this:

```swift
.onDelete { indexSet in
    for index in indexSet { modelContext.delete(sortedBookmarks[index]) }
}
```

`sortedBookmarks` is a *computed property* over `book.bookmarks`, re-evaluated on every subscript.
Delete offset 0 and the array shrinks, so offset 1 addresses what was offset 2 — wrong annotation
deleted, or out of range.

I wrote "reachable from edit-mode multi-select" into both the ledger and Sol's brief before
checking. **OBSERVED, after: there is no `EditButton` anywhere in the app** (`grep -rn
"EditButton\|editMode" SpeedRead/Views/` returns nothing), so `.onDelete` is reachable only by
swipe, which passes exactly one index. **The bug is latent, not user-reachable today.** It becomes
live the moment anyone adds an `EditButton` — which is a normal thing to add and carries no warning
that it arms a data-loss bug two files away.

That is the fifth time this session a plausible explanation arrived ahead of a check that was
already in hand, and the cheapest one yet: the codebase was open, and the grep was six seconds.
The correction does not change what to build — resolving offsets against one snapshot is still
right, still matches `ServerListLogic.serversToDelete`, and makes the failure unrepresentable
rather than merely absent — but it changes the honest claim from "fixes a live bug" to "closes a
latent one and unifies the rule", and Sol was briefed on the wrong version.

11 tests written first (`SpeedReadTests/AnnotationListLogicTests.swift`), specifying a type that
does not exist — ordering including a creation-time tiebreak (Swift's sort is introsort and NOT
stable, so two annotations at one position could reshuffle between renders), snapshot-resolved
deletion, 1-based display labels, and the U+2013 EN DASH verified in the source bytes of both files
(`e2 80 93`). Dispatched to Sol as spec, not script; the brief forbids editing the tests, forbids
unifying the two surfaces' deliberately different visual designs, and forbids adding delete to the
reader — whether the reader *should* delete is a product question for the operator, not one to
answer by implication.

**Found while scoping and deferred to leg 14 — with my first framing of it measured and corrected.**
`RemoteBookDetailView.ensureExtension` returns the filename unchanged whenever
`NSString.pathExtension` is non-empty, so a server-supplied filename with no real extension but a
dot in it never gets its mime-derived extension patched in, and `DocumentImporter` (which routes on
extension) mis-routes it. The user sees an extraction failure rather than "unsupported format".

I was about to write "Vol. 2", "J. R. R. Tolkien", "A Tale of Two Cities. Abridged" into the spec as
triggering cases. MEASURED instead (`swift` one-file probe, 2026-09-03):

| filename | `pathExtension` | triggers |
|---|---|---|
| `Book v1.2` | `"2"` | **yes** |
| `Vol. 2` | `""` | no |
| `J. R. R. Tolkien - The Hobbit` | `""` | no |
| `A Tale of Two Cities. Abridged` | `""` | no |
| `file.` | `""` | no |
| `Dracula.epub` | `"epub"` | no — correct behaviour |

`pathExtension` excludes a trailing token containing a space, so **three of my four examples were
wrong** and only the version-number shape triggers it. The defect is real and narrower than I had
it: it needs a dot followed by a space-free token — `Book v1.2`, `Novel.Part2`, `The Hobbit.1937`.

Had I not measured, three false cases would have gone into a brief as the spec's premise, and the
delegate could not have caught them because I supplied the oracle — exactly
`[[reference-briefs-carry-the-managers-oracle]]`. The probe cost one `swift` invocation.
No test names that file today.

## 5y. Leg 13 killed at load 64 — the ceiling is not a count of builds (2026-09-04)

Leg 13's code landed; its **verification** was killed by the OS for memory. Fourth leg reaped this
session. State at the kill (OBSERVED):

```
load averages: 64.74 71.43 39.40
vm.swapusage:  total 14336.00M  used 13971.06M  free 364.94M   (swap had GROWN from 11264M)
real xcodebuild processes: 1 (not mine)
```

`CLAUDE.md` says the local ceiling is "about two concurrent build/simulator agents". **Measured
tonight, two was too many** — and the count was never the right unit. What was actually resident:

| holder | artefact | size |
|---|---|---|
| peer session `fd0f3e53` | `peer-cleanclone` DerivedData | 4.5G |
| peer session `fd0f3e53` | `peer-tests` DerivedData | 4.6G |
| unleased | `peer-probe-coverage-probe` DerivedData | 4.4G |
| peer session | `eph-cleanclone-56164` booted simulator | ~4.5G measured |
| this session | `speedread-tests` DerivedData | 340M |

Two *builds*, but four multi-gigabyte working sets. **The ceiling is aggregate resident footprint —
DerivedData trees, booted simulators, and the compile itself — not a process count.** A count
happens to correlate when every project is the same size, which is why the rule survived until a
4.6 GB tree sat next to a 340 MB one.

### The part neither of us could have read better

I dispatched at load 3.37, swap 557M free, one unrelated build running. That was an honest read and
it was the right call on the evidence. The peer had told me their v2 "has a capacity gate and will
wait for you rather than race you", and it did not hold. Neither fact is the lesson.

> **A capacity check is a snapshot taken at dispatch; a 30-minute build is exposed to everything
> that starts during the other 29.** No amount of care at t=0 bounds what arrives at t=5, because
> neither session can see the other's queued work.

So the fix is not a better reading before dispatch. It is one of: a machine-wide lock (nobody has
built one), or **accepting that kills happen and making legs cheap to resume** — which is what
already saved this one. The `thread_id` was captured at dispatch per the harness rule, the code was
written before the build started, and the loss is one `coverage.sh` run rather than a leg.

**Design consequence I am adopting: put the authoring before the verifying, always, and never let a
delegate hold the only copy of a decision.** Sol wrote all four call sites and the logic type before
touching a simulator; every one of those edits survived the kill. Had the brief said "verify as you
go", the kill would have taken the work with it.

### What leg 13 actually produced, unverified

`AnnotationListLogic` (56 lines, own file) with `ordered`/`bookmarksToDelete`/`highlightsToDelete`/
`positionLabel`/`rangeLabel`; all four annotation lists routed through it; both computed
`sortedBookmarks`/`sortedHighlights` properties gone, replaced by a `let` in `body` that the
`.onDelete` closure captures — one snapshot, which is the fix.

Sol went **beyond the spec** on ordering: after `wordIndex` and `createdAt` it falls back to
`id.uuidString`, making the order total even for two annotations sharing a position *and* a
timestamp. My spec required only the `createdAt` tiebreak. The addition is correct and no test
exercises it — noted as a mutation candidate rather than pretended to be covered.

**Status: code complete, ZERO of it verified.** No build, no test run, no coverage figure. Nothing
here is a claim about behaviour until `Scripts/coverage.sh 82` is green.

## 5z. The lane hangs on the Crucial X8, and the constant nobody varied (2026-09-04)

Leg 13's verification did not fail. It **hung**, and the signature is unambiguous:

```
pid 90529   elapsed 23:25   CPU time 0:06.89   %CPU 0.0
output lines: 0
```

Twenty-three minutes of wall clock for seven seconds of CPU. Blocked, not working. The DerivedData
tree was `/Volumes/Crucial X8/DerivedData/speedread-tests` — **343 MB**.

A peer session independently isolated the same effect on a different repo by varying one thing:
`-derivedDataPath` on the boot volume instead of the X8. Their lane went from 6–9 minutes of hanging
with 0 tests, every time, to `Executed 1121 tests … ** TEST SUCCEEDED **` in 2m56s, matching their
CI ground truth exactly. Seven failures across two surfaces (xcodebuild's `DVTFilePath` walk, and
Python's `os.scandir` raising `InterruptedError` inside `dd-lease`) collapse to one cause.

**My 343 MB tree matters to their investigation**, because it removes the hypothesis they had spent
the night on: their tree was 4.6 GB and they had assumed size. 343 MB behaves identically. Whatever
this is, it is a property of the volume, not of tree size. Their leading guess is TCC on a removable
volume re-evaluated when a launchd service restarts — `stat` still works while directory listing
stalls. ASSUMED; the volume correlation is OBSERVED and reproducible on two repos.

Timeline that fits: the X8 mount dir ctime is 2026-09-03 14:45:15 and all six self-hosted runners
restarted 2026-09-03 20:15:2x, both **after** the last known-good CI run on 2026-09-01 21:24:46.

> **This contradicts standing project policy.** `CLAUDE.md` and the operator's global doc both route
> DerivedData to the X8, and the rule includes "don't silently fall back to the boot drive". So this
> fallback is deliberate, temporary, and stated out loud rather than silent — boot volume has 41 GB
> available and the tree is under 1 GB. It is for the operator to decide whether the policy changes.

### The lesson, which is the peer's and is the best thing either of us produced tonight

They varied fresh DerivedData, ephemeral simulators, a clean clone, a capacity gate, CI versus
local — and every single variant held the X8 fixed, because "DerivedData lives on the X8" is
*policy*, and policy reads as background rather than as a variable.

> **What is constant across all of my failing runs BECAUSE a rule says it should be?**

That question is now part of this project's debugging checklist. A convention is the hardest
variable to see precisely because following it feels like not making a choice.

### Two self-inflicted errors in the same five minutes, recorded

1. I killed the hung build with `pkill -x xcodebuild` and took the peer's actively-compiling build
   with it — both PIDs were on my screen one command earlier. `-x` made the matcher precise and did
   nothing about the verb's scope. **Identify by pattern, act by PID.** Told them immediately, with
   a discriminator, because a SIGTERMed run resembles the hang they were collecting evidence for and
   a bad sample that agrees with a correct conclusion is the hardest kind to find later.
2. I ran the gate as `Scripts/coverage.sh 82 2>&1 | tail -60`. The task reported **exit code 0**
   while the log ended in `** BUILD INTERRUPTED **` — `tail`'s status, not the script's. Third
   instance of the wrapper trap, in the same session I wrote the rule down. A display convenience
   silently became the status reporter.

The failure-evidence preservation step worked correctly and kept the artifact:
`/Volumes/Crucial X8/agent-artifacts/speedread-lane-failures/20260904-003843-iOS-hermetic-unit-lane`.

## 5aa. Writing a doc comment lowered the coverage figure (2026-09-04)

The boot-volume run executed 288 iOS + 65 watchOS tests, `** TEST SUCCEEDED **` on both lanes —
and then failed the gate:

```
Combined ATTRIBUTABLE: 78.41% (7368/9397)      Required: 82%
```

Against 84.42% two days earlier. Nothing about the app got worse. What happened is that
`BookmarkListView.swift` (0/298) and `HighlightListView.swift` (0/373) entered the ATTRIBUTABLE
denominator. Remove those 671 zero-covered lines and iOS reads 5604/6585 = 85.10%.

A file counts as attributable when a test **names a type it declares**, and the match ran against
raw test source. The only mentions of those two types anywhere in the suite are in a doc comment
**I wrote three hours earlier**:

```swift
/// Specification for the decisions shared by the four annotation lists: `BookmarkListView`
/// and `HighlightListView` (RSVP) and `ReaderBookmarkPicker` / `ReaderHighlightPicker`
```

Arithmetic that identifies it without guessing: iOS excludes 10195−7256 = 2939 unnamed lines; the
GHOST files account for 761 of them; the 0%-covered file list totals 2849, so 2849 − (2939 − 761) =
**671 named-and-zero-covered lines — exactly 298 + 373.**

### Why this is the worst-shaped bug of the night

> **An accurate doc comment lowered the measured coverage, and the fastest route back to green is
> to delete the comment.**

Every other instrument failure this session cost a wrong number. This one puts a thumb on the scale
against documentation and rewards laundering, and the laundering looks like tidying. Any metric
that reads prose will eventually be gamed by editing prose — including by a well-meaning agent that
"just cleans up a comment" to unblock CI and never learns what it did.

### Fixed properly, in the instrument

`strip_comments` now walks the source before matching. It has to walk rather than regex, for two
reasons that are both live in this repo: Swift block comments **nest**, and `//` appears inside
every `https://` string literal — a naive stripper eats the rest of that line and deletes real
references. String literals are deliberately **kept**, because a type named in a string is a real
reference (accessibility identifiers).

`python3 Scripts/attributable-coverage.py --self-test` is a fifth CI honesty gate: 9 cases asserting
**both directions**, verified by breaking the stripper each way —

| injected fault | caught |
|---|---|
| line comments not stripped (the original bug) | 3 assertions |
| `//` inside strings treated as a comment | 1 assertion (`https://x` destroyed) |

### The uncomfortable part I am not hiding

After the fix, those two views become *unnamed* and vanish from ATTRIBUTABLE entirely — and since
they have zero covered lines they do not even appear under GHOST. **The number goes back up by
excluding two genuinely untested files.** That is the metric behaving as designed, and it is
exactly why the framing has three numbers: REACH is the one that still carries them, as
`42 of 55 files named`. `BookmarkListView` and `HighlightListView` have no behavioural tests, leg
13 did not give them any, and no single number will say so.

### And a preservation step guarding the wrong event

The lanes passed; the gate failed; `coverage.sh` deleted its work dir and every coverage JSON with
it, so diagnosing a threshold failure cost a full rebuild. Failure evidence was preserved for a
*lane* failure and nothing for a *gate* failure — the case where the lanes are green and the only
question is which files moved. The JSONs are kilobytes. `preserve_gate_evidence` now keeps them.
Same shape as the `if [ -e ]` with no `else`: the step existed and was guarding the wrong event.

## 5ab. I disabled CI and it looked exactly like a normal push (2026-09-04)

Pushed four commits at 04:49:59Z. Watched the runner logs. Nothing. Not a failure — **nothing**.

```
_work mtime:            2026-09-01T20:36:48Z     (three days stale)
newest Worker log:      2026-09-01 20:39:23Z
runner:                 alive, "Listening for Jobs" since 00:15:30Z
runner heard since push: nothing
```

`actionlint` named it in one line:

```
ci.yml:32:36: context "runner" is not allowed here.
  available contexts are "github", "inputs", "secrets", "vars"
```

My DerivedData fix put `${{ runner.temp }}` in the **workflow-level `env:` block**, where the
`runner` context does not exist. GitHub could not parse the file, so it created no run at all.

> **CI did not go red. CI stopped existing.** The push succeeded, the tree was clean, the local
> gates were green, and every signal I habitually check was normal. The only evidence was an
> absence, and absences are what nobody looks at.

This is the sharpest instance yet of the thing this whole ledger is about — I have been building
gates all night against tests that cannot fail, and I shipped a change that made *every* gate
unable to run, in the one file that decides whether any of them run.

### The structural point: a gate cannot live only inside the thing it guards

I could have "fixed" this by adding an actionlint step to `ci.yml`. **That step would never have
executed**, because an unparseable workflow means no run. The validity check has to sit *outside*
CI, which means locally, before the push.

`Scripts/honesty-gates.sh` is now the single list of all six gates, cheapest first, actionlint
first of all. CI runs the same script rather than restating the list — it previously lived in CI
steps *and* in CLAUDE.md prose, and a list in two places is a list that disagrees with itself. If
actionlint is not installed the script **fails** rather than skipping: an unrunnable gate that
returns success is the exact shape of everything deleted from this repo this week.

`.github/actionlint.yaml` declares the `speedread` self-hosted label, because an unknown-label
warning on every run buries the real error — which is how a gate stops being read.

### Two smaller things fixed while in there

- I had left `SPEEDREAD_LANE_MARKER: ci` in the workflow env purely so a comment had somewhere to
  attach. Dead config to host prose. Removed; the rationale moved to the step it explains.
- The X8 guard's message still read "refusing to build onto the boot drive" after DerivedData had
  deliberately moved *to* the boot drive. A guard whose message contradicts its purpose is worse
  than no guard, because the next reader trusts the message and not the code.

### Standing question this earns

`actionlint` was installed on this machine the whole time and I had never run it. The question to
ask of any config that gates execution — workflow, launchd plist, test plan, Xcode scheme — is not
"does it look right" but **"what would tell me if this file stopped being honoured at all?"** If
the answer is "the thing it configures would go quiet", that is not a signal, and a validator that
runs outside it is owed.

## 5ac. Leg 13 mutation results — 6/6 killed, and three attempts to get there honestly

```
6 killed · 0 survived · 0 invalid/skipped · 0 UNEXPECTED · 0 replayed
elapsed: 51s 37s 33s 35s 34s 36s   (no outlier — no mutant went off doing hidden I/O)
```

`AnnotationListLogic`'s ordering (both overloads), both 1-based labels, the U+2013 en-dash, and
snapshot-resolved deletion are all genuinely covered. Getting that number took three runs, and each
failure was a different honest refusal by the harness rather than a flake to shrug at.

### Attempt 1 — OS-killed mid-mutation, and it left a live mutation in the tree

Memory pressure reaped the run between mutations. `AnnotationListLogic.ordered(_ highlights:)` was
left with its comparison flipped in the working tree — **a one-line diff indistinguishable from a
deliberate edit of mine.** A `git add` before looking would have committed a reversed comparison
under my own name.

`--restore` put it back in one command and **needed no simulator**. That is the design rule
`[[reference-mutation-gate-design]]` already recorded — *the recovery path must not need what the
normal path needs* — being exercised for the first time since it was written. An earlier version
read `SPEEDREAD_IOS_DESTINATION` at import, so `--restore`, the one path that runs after a crash,
died with a `KeyError` before it could restore anything.

**Standing rule: after any killed run, `--restore` before anything else, and certainly before
`git add`.**

### Attempt 2 — 6 killed, but one verdict was REPLAYED, not measured

The gate resumed from its JSONL ledger and printed
`KILLED (REPLAYED from ledger, not re-measured)`. **It labelled itself**, unprompted, which is the
honest-third-verdict design working — a gate that silently replayed would have handed me "6 killed"
with one verdict laundered from a run the OS had killed. I deleted the ledger rather than report it.

### Attempt 3 — one INVALID, and the cause was my own shortcut

```
[3/6] position label drops the 1-based offset:
      INVALID — no test ever executed — a build failure is not a kill
```

Cause, read from `/tmp/mut-3.log` rather than assumed:

```
Simulator device failed to launch com.legitimateapps.SpeedRead
  FBSOpenApplicationErrorDomain Code=6 "Application failed preflight checks"
  reason: Busy
```

Not a compile error, nothing to do with the mutation. **I had passed a NAME-based destination
(`name=iPhone 17 Pro`) instead of leasing a simulator**, so the run raced whatever else on this
shared machine wanted that device. The house rule exists for exactly this and I skipped it for
convenience.

> A two-verdict gate would have recorded that build failure as a pass. The INVALID verdict's second
> real catch — see §5u for its first.

Attempt 4 leased `cc-speedread-i17p-1ec8`, deleted the ledger, and measured all six fresh. Lease
released; zero simulators booted afterwards.

**What this run does NOT establish:** `BookmarkListView` and `HighlightListView` still have no
behavioural tests of their own. The mutations cover the extracted logic, not the views' rendering.
REACH continues to carry that as `40 of 55 files named`.

## 5ad. Leg 14 — one answer to "which formats can we read" (2026-09-04)

Three places decided independently which formats SpeedRead can read, and they already disagreed:

| location | form | knew |
|---|---|---|
| `DocumentImporter` | `switch ext` | pdf, epub, txt/text, rtf |
| `RemoteBookDetailView` | mime whitelist | the same five mime types |
| `OPDSAtomParser.displayFormat` | mime switch | **also MOBI, AZW, HTML** — which we cannot read |

`SupportedFormat` is now the single source; the importer routes through it and the OPDS detail
view filters through it. `displayFormat` still advertises MOBI/AZW/HTML — that is a display-only
UX question, deliberately raised and NOT decided here.

### Two real bugs closed, both specified before the code

**A version number is not a file extension.** `ensureExtension` returned the filename unchanged
whenever `pathExtension` was non-empty, and MEASURED, `"Book v1.2"` has pathExtension `"2"` — so an
EPUB served under that name never got `.epub` appended and `DocumentImporter` threw
`unsupportedFormat`. The right question is not "is there an extension" but "is there one the
importer can route". (`"Vol. 2"` and `"J. R. R. Tolkien"` do NOT trigger it — pathExtension
excludes a trailing token containing a space. Three of my four original examples were wrong and the
probe caught them before they reached the spec.)

**Case-sensitive title derivation.** `filename.replacingOccurrences(of: ".\(ext)")` with `ext`
already lowercased meant `"Dracula.TXT"` matched nothing and the extension stayed in the title. Sol
replaced the whole expression with `deletingPathExtension`, which is better than what the spec asked
for. It also chose `acquisitions.indices.contains(index)` over the upper-bound-only guard I
specified, closing the negative-index crash more directly.

### Verification

20 tests written before the code. `Scripts/coverage.sh 82`:

```
iOS 308 tests · watchOS 65 tests · Combined ATTRIBUTABLE 84.56% (7444/8803) · PASS
```

**Run twice on the same commit and leased device: 7444/8803 both times, 0 differing rows across 81
files.** So coverage measurement is deterministic *on this repo* too, independently replicating a
peer's null on a different repo with a different framework mix. That licenses treating any per-file
delta as signal rather than re-running to check for flakiness.

Sol reported 84.63% (7450/8803) — same denominator, **6 more covered lines**. Since my own figure is
reproducible, that difference is real rather than spread; the cause is NOT established, most likely
a different simulator than my leased clone. Recorded rather than averaged away.

Mutations: **7 of 7 KILLED**, none survived.

### The simulator degrades with repeated installs, and the gate now handles it

Mutation 7 came back INVALID with:

```
FBSOpenApplicationErrorDomain Code=6 "Application failed preflight checks"  reason: Busy
```

on a **leased** device, after six consecutive successful mutations — so leasing was not the whole
story. Re-run on a freshly leased simulator: KILLED. Same signature had appeared in leg 13's
mutation 3. Twice is a pattern, not a flake.

`simulator_refused_to_launch()` now distinguishes that from a real build failure and recycles the
device (`simctl shutdown` + `boot`) for **one** scoped retry. Deliberately narrow: a blanket retry
would hide real flakiness, so it fires only on a reproduced signature whose fix is known to work,
it still records INVALID if the retry also fails, and **every retry is printed and written into the
report** — a retry nobody sees is a retry that hides a degrading machine.

Controlled three ways: fires on the real `mut-7.log`, stays quiet on a healthy lane, and stays
quiet on a genuine compile error — the last matters most, because retrying a real INVALID would
mask exactly what the verdict exists to catch.

## 5ae. Leg 15 — a rating prompt, honest format badges, and two mutants that covered for each other (2026-09-04)

Operator decisions, 2026-09-04 (verbatim where it matters): ship 1.2 with both features folded in ·
rating prompt "once they launch it the third time, not triggered on anything but like onAppear for
the main view or whatever or root view" · unreadable OPDS formats "grayed out" with a route to ask
for support — pointed at `https://www.legitimateapps.com/contact` because the GitHub repo is private
and making it public would publish PII in commit history and break the self-hosted-runner rule.

**Shipped:** `Services/ReviewPromptLogic.swift` (decision + once-per-process gate),
`Views/Server/OPDSFormatAvailabilityLogic.swift` (readable/unreadable split, deduplicated badge
names, the support URL as a tested constant). `RemoteBookDetailLogic.supportedAcquisitions` now
delegates to the one classifier instead of running its own filter. Badges in the browse row and
detail view tint by readability; the detail view shows the copy and a `Link`.

**Method, honestly:** Sol was OOM-killed mid-leg with the review half complete and the OPDS half at
tests-but-no-implementation. Every edit survived on disk — author before verify, again. I finished
the implementation myself against Sol's tests (deviation from routing; the remaining work was
spec'd to the line and a second dispatch meant another 30-minute cycle on a machine that had just
killed one). **RED was not observed** for these ten tests. The mutation gate is the substitute and
is stronger — it is red-first performed systematically after the fact.

**Mutation gate: 7 killed · 0 survived**, measured from an empty ledger on a fresh device.

The first pass was **5 killed · 2 survived**, and both survivors had one cause:

```swift
guard storedLaunchCount < terminalLaunchCount else { … }          // caps at 4
let thisLaunchCount = min(currentLaunchCount + 1, terminalLaunchCount)   // caps at 4
```

Two mechanisms clamping the same value. Mutate the guard's comparison and the `min()` still answers
4; mutate the `min()` away and the guard already returned. Each mutant was equivalent **only because
the other line existed** — no test could distinguish either, and no test should have to. Kept the
guard (it also prevents `Int.max + 1` trapping), deleted the `min()`, and **retargeted** the
orphaned mutation onto the surviving line rather than dropping it — a mutation that vanishes because
its anchor is gone is how a suite stops being pinned with nobody noticing.

**Two instrument mistakes in this leg, both mine:**
- Deleted `docs/testing/mutation-report.jsonl` and re-ran — **6 of 7 verdicts REPLAYED**. The ledger
  follows `--out`, so it lived in the scratchpad. The gate said so on every row and I still nearly
  read a stale SURVIVED as a measurement. Now: `find` for `mutation-report*.jsonl` and verify the
  find is empty before the run.
- A `| tail` swallowed a nonzero exit when the scoped mutation list had been wiped by a reboot; the
  wrapper said `exit=0` over a traceback. Third instance of this exact trap in the ledger.

iOS lane on the final tree: 318 tests in 41 suites (was 308). Honesty gates 6/6.
Mutations 41 → 48.

**Behavioural verification, OBSERVED 2026-09-04 18:28 EDT** on leased sim `C81647D8`, Debug build
from `045a4f7`, three cold launches with `-hasCompletedOnboarding YES`: launches 1 and 2 show the
library and nothing else; launch 3 shows the native StoreKit rating sheet over the library;
`reviewPromptLaunchCount` in the app's Preferences plist reads `3` afterwards. Frames in
`docs/testing/evidence/leg15-*.jpg`. The unit tests pin the decision; this pins the wiring the
unit tests cannot see.

## 5af. The watch could not open a book — found by taking a screenshot (2026-09-04)

Recapturing App Store screenshots meant walking the watch the way a user does: pair, receive a
book, tap **Now Reading**. What appeared was a sheet with system chrome and nothing in it — no word,
no play button, no WPM — and Close did nothing. The a11y tree carried **three** "Close" buttons.
The watch log carried the cause:

```
UIKit:Presentation  Attempt to present <PresentationHostingController> on <SPHostingViewController>
                    … which is already presenting <PresentationHostingController: 0x10585b200>.
```

`.sheet(isPresented: $showRSVP)` was attached to a `Section` inside the library `List`. On
watchOS 26 that modifier is applied per row host, so two hosts raced to present one binding; the
phantom won and UIKit refused the real RSVP sheet. Present since `6ea9479`, long before this mission.

**Every route to reading on the watch goes through that sheet.** The detail view's "Read" button
only selects the book and pops back to the library. So the shipped watch reading flow is broken on
current watchOS, and nothing knew: the only watch UI test launches straight into RSVP through the
`--ui-test-crown-direction` fixture and never touches the library. This is the gap
`project_speedread_2026_08_state` recorded as "watch E2E still unverified", now with a body.

**Red first, for the right reason.** A new `--ui-test-seeded-library` destination seeds the same
fixture book but shows the *library*; `NowReadingOpensRSVPUITests` taps the row and asserts
`watch-rsvp-position` exists. First run failed on its own precondition (the row's label is
"title, 50%", not the bare title) — a red that fails before reaching the claim proves nothing, so
the row got `watch-now-reading` and the run was repeated until it failed on the assertion that
matters. Then the sheet moved to the navigation content: one presenter, one binding.

Lesson worth its own line: **a screenshot is a behavioural test with a human oracle.** The unit
suite was at 84% attributable and 373 tests when this was found, and none of them could see it,
because presentation is a UIKit fact, not a SwiftUI-body fact.

**Found while re-verifying, not yet fixed:** running the watch hermetic lane un-cloned on the
leased device replaced its real library with the `"Received" / "Author"` two-word book from
`WatchSyncServiceCharacterizationTests` (lines 99, 117). Those tests drive a service whose store
points at the real `Documents/watchlibrary.json`; `WatchLibraryTests` injects a temp directory
and does not leak. CI is unaffected (XCUITest and clean clones), but a "hermetic" suite that
writes user data on the device it runs on is not hermetic. Fix: inject the store URL in the
characterization tests. Queued behind the release leg.

## 5ag. The Settings gear was drawn three points past the edge of the watch (2026-09-04)

Found by the capture driver's failure, not by a test: `Failed to scroll to visible … Button
{{211.0, 64.5}, {36.0, 36.0}} label: 'Settings'` on a 208pt-wide Series 10 (46mm). `RSVPWordView`
lays out twelve fixed-width characters each side of the pivot — at the watch's 18pt that is 302pt
of width — and the paused surface's `VStack` takes its widest child, so the X…gear `HStack` spanned
302pt centred on a 208pt screen. The X survived on the left; the gear left the screen on the right.
Present in the tree, drawn nowhere, tappable by nobody. Long-press still opened settings, which is
why nobody noticed. Red first: `testSettingsControlIsOnScreenWhenPaused` walks the real path and
asserts the control's frame lies inside the window and is hittable — failed on both. First fix
— `.frame(maxWidth: .infinity).clipped()` — compiled, ran, and changed nothing: the control stayed
at x=211. A flexible frame does not shrink a child that insists on being wider; it adopts the
child's width, so there was nothing to clip. A frame dump then showed the surface's OWN close
button at **x=−39**: both edge controls were off-screen, and the X visible in the screenshot was
the sheet's system close, not ours. Second fix: a fixed-width frame at the device's screen width,
which is authoritative, then clip. Lesson: a fix that compiles and runs green-looking on a screen
you did not measure is a hypothesis. Measure the frame.

Follow-up, not done here: `maxSideChars` is a constant. It should derive from available width so
long words are shown rather than clipped at the edges on small screens.

## 5ah. The controls fix exposed a second close button (2026-09-04)

With the row on screen, the paused surface showed two X controls stacked at the top-left: the
sheet's system close and the surface's own. In production RSVP is always presented as a sheet, so
the surface's X was always a duplicate — invisible only because it had been laid out at x=−39.
Explicit close and `onDisappear` commit the same position (`close` only marks the dismissal so the
disappear path does not commit twice), so the X carried no behaviour the system control lacks.
Red first: `testPresentedRSVPHasExactlyOneCloseControl`. First assertion was "exactly one" and
would have failed forever — watchOS lists its own close control three times in the tree — so it
became "the surface contributes zero `xmark`, the sheet contributes at least one." Removed the X,
the `onClose` parameter, and the view's now-unused `dismiss`. Watch UI 4/4.

Three findings from one screenshot pass (§5af, §5ag, §5ah), none reachable by a unit test.

## 5ai. The long-word clip, and a fix that had to change the mechanism (2026-09-06)

`RSVPWordView` reserved `charWidth * 12` on each side of the pivot plus one character for the
focus — 25 character widths, unconditionally, at every font size. At the iPhone's default 32pt that
demanded 544pt of a 393pt screen; at the watch's 18pt, 302pt of 208pt. **Both platforms overflowed,
and had since the view was written.** §5ag had treated this as a watch layout bug and clamped the
symptom with `.frame(width: screenWidth).clipped()`, which stopped the overflow from pushing the
sibling controls off-screen but still cut the word in half — the clip was a containment, not a fix.

The fixed columns exist for a reason: the ORP focus letter must not move between words, which is
the whole point of RSVP. So the fix could not be "let the HStack size to content". Red first, at
the pixel level:

```
Watch renderer: (CGFloat(image.width) → 302.0) <= (width → 208.0)
iOS renderer:   (CGFloat(image.width) → 544.0) <= (width → 393.0)
Fit arithmetic: (fit.trailingEdge → 470.0) <= (width → 208.0)
```

`RSVPWordFit` computes a uniform scale — `min(1, availableWidth / (2·max(before, after) + focus))`
— from measured segment widths, keeping the focus centre fixed at `availableWidth / 2`. Words that
already fit are untouched (scale 1); only a word that would overflow shrinks, which is strictly
better than showing half of it. The view had to move from an `HStack` of three `Text`s to a
`Canvas`, because a scale factor derived from *measured* text needs the measurement, and a fixed
frame cannot supply one. `.clipped()` came back off both call sites: with the word fitting, the
fixed frame alone is what keeps the sibling controls on screen.

The assertions are pixels, not geometry: ink inside the 16pt padding, the red focus letter's centre
within 1px of the screen centre, ink straddling the centre. `RSVPRenderProbe` cannot pass
vacuously — it resolves its bounds through `#require(columns.min())`, so a render with no ink, or
with no red pixel where the focus should be, fails rather than returning a degenerate box.

Follow-up, not done here: `Canvas` re-resolves and re-measures its text on every draw, and RSVP
redraws 5–16×/second. The previous version rebuilt three `Text`s per word, so this is not a new
cost in kind — but it has not been measured on a watch.

## 5aj. Hermeticity belongs at the seam, not in the test plan (2026-09-06)

`WatchSyncService` reached its persistence through `static var libraryURL`/`libraryStore`, so every
instance — including one built by a test — wrote the real `Documents/watchlibrary.json`. The watch
unit lane overwrote the library on whatever simulator or device it ran on.

The first attempt set `SPEEDREAD_HERMETIC_TESTS=1` in `WatchHermetic.xctestplan`. That was
reverted: **a hermeticity fix that lives in a test plan is absent the moment the suite is run
un-plan'd**, which is exactly when nobody is watching. The fix is injection at `init` alongside the
existing `session` parameter, with `legacyBookURL` derived from the injected store's directory so
the legacy-migration path is isolated too.

Proved without the plan, which is the only proof that counts here: the generated `.xctestrun` had
its `EnvironmentVariables` stripped, the lane ran `test-without-building` under `env -u`, all 70
tests passed, and the real `Documents/watchlibrary.json` was byte-identical before and after
(SHA256 `ef314936…`, 288 bytes).

**Manager's error, recorded because the delegate could not have caught it.** The brief asserted that
`Scripts/shared-source-audit.py` refuses a duplicate filename across the two *test* trees. It does
not — `TREES` is `("SpeedRead", "SpeedReadWatch Watch App")`, the source trees only. That constraint
came from a summary rather than from reading the script, and a false constraint supplied by the
manager is invisible to the delegate because the manager is the oracle. It cost nothing this time —
renaming to `WatchRSVPWordFitTests.swift` was right on the naming convention alone — but the
shared `RSVPRenderProbe.swift` that landed in both test trees is a symlink by the delegate's own
judgement, not because any gate required it. Extending the audit to the test trees is the fix.

## 5ak. Two traps in one leg: GHOST coverage and a shadow that masks its own claim (2026-09-06)

Legs 19 and 20 began the push to close the attributable gap. The measured starting point: 18 files
named by no test — 3,528 executable lines on iOS, 477 on watch — every one of them SwiftUI markup
whose decisions had already been relocated into `*Logic` files.

**The arithmetic has to come first, because the metric moves the wrong way if it does not.** Naming
a file moves its *whole* line count into the ATTRIBUTABLE denominator. Naming all 4,005 remaining
lines without covering them would have taken 84% to roughly 55%, the gate would have failed, and
the pressure would have been to lower the floor — the one move never allowed. So each leg has to
*cover* what it names:

| | attributable | denominator |
|---|---:|---:|
| before leg 19 | 85.12% | 9,003 |
| after leg 19 (annotation lists) | 85.88% | 9,674 |
| after leg 20 (launch + settings) | **86.72%** | **10,396** |

Nearly 1,400 lines entered the denominator across the two legs and the number rose both times.
Floor ratcheted 82 → 84.

**Trap one: three of leg 20's five files already showed high coverage.** `OnboardingView` 269/286,
`ContentView` 42/45, `SpeedReadApp` 15/15 — entirely because a host test bundle launches the app and
renders them with nothing asserting. That is GHOST, and naming those files to harvest it is exactly
the laundering the attributable gate exists to refuse. Each was pinned on a real claim instead: the
three onboarding pages differ in content, the gate switches both ways, the review prompt is claimed
at most once per process, and the SwiftData container holds all four models — a model missing from
that list is a runtime crash and nothing noticed before.

**Trap two, and this one is subtle.** The new onboarding UI test first used
`-hasCompletedOnboarding NO` to force onboarding to appear regardless of what a previous run left
on the simulator. It failed at the library assertion, and the reason is that the mechanism masks
the thing under test: **the argument domain outranks the persistent domain on read.** Completing
onboarding writes `true`, `@AppStorage` reads back the shadowed `NO`, and `ContentView` never
advances. The assertion could not have passed in any universe. The isolation that made the test
repeatable is the same fact that made it incapable of proving anything. `--reset-onboarding` clears
the real value instead — inside `#if DEBUG`, never a runtime check alone.

Worth stating plainly: **every existing UI test skipped onboarding**, so the first screen every new
reader sees had never been driven by any test until this leg.

**A capture method is a hypothesis too.** The onboarding render assertion failed first against
`view.layer.render(in:)` on a paged `TabView`. The delegate correctly refused to call it either a
bug or an artifact without evidence. It is an artifact — `TabView(.page)` is a
`UIPageViewController` and `layer.render` does not reliably traverse its child containers — and the
fix was not a better capture but a better split: assert page *content* in a unit test where it is a
real claim, and page *transitions* in a UI test where paging actually lives. The rejected middle
path was injecting a page `Binding` into `OnboardingView` so a unit test could drive the TabView:
production API widened for a test is a shim, and it would have bought a weaker claim than the one
the UI test now makes.

## 5al. Two gates that were real, passing, and in the wrong place (2026-09-06)

Neither of these was a broken control. Both were correct, both reported honestly, and both had
never once said anything false. They were still worth fixing, and the reason is the interesting
part: **where a gate lives decides whether it can do its job, independently of whether its logic
is right.**

### The audit that could not see half the repo

`shared-source-audit.py` exists because `SpineColor.swift` was a real copy in both source trees and
had silently diverged — iOS grew a themed-palette overload the watch never got. The script turns
"these are one file" from a diff someone remembers to run into a property the build enforces.

Its `TREES` constant named the two *source* trees. The two *test* trees were never scanned. That
matters because `RSVPRenderProbe.swift` now exists in both test trees, and it is a symlink for one
reason only: the delegate who wrote it in leg 18 chose to make it one. No gate required it. Had
they copied it instead — the obvious thing to do — the two probes would have been free to drift,
and the failure mode is worse than the source-tree one it was built for. A drifted source copy
renders the wrong colour, which somebody eventually sees. A drifted *test* copy removes an
assertion from one platform's lane and leaves that lane reporting green.

Exemptions are keyed per pair now, because an argument for keeping a shipping source file separate
is not an argument about a test file that happens to share its name.

Controls, run rather than assumed: a real duplicate across the test trees fails the audit; a
symlinked one passes; a stale exemption naming a file that is not in both trees fails.

### The gate that cost two simulator boots to reach

`network-isolation-audit.py` is a static text scan. It takes about 200 ms. It enforces two
genuinely different platform facts — on iOS, global `URLProtocol` registration covers
`URLSession.shared` but *not* a session built from a custom configuration, so custom sessions are
centralized in the harness file; on watchOS, global registration was observed not to intercept
`URLSession.shared` at all, so the watch trees may not use it.

It was invoked from exactly one place: line 40 of `Scripts/coverage.sh`. Reaching it therefore
required booting two simulators and running both hermetic lanes. Meanwhile
`Scripts/honesty-gates.sh` opens by describing itself as "the SINGLE LIST of what must be true
before a build is worth starting" — a claim that was, quietly, false.

Nothing ever drew attention to this, because the gate passed every time it ran. That is the whole
lesson. A gate that fails in the wrong place announces itself. A gate that *passes* in the wrong
place is invisible, and the cost is paid only on the day it finally has something to say — when
the news arrives fifteen minutes and two simulator boots later than it could have.

It surfaced here for a mundane reason: leg 21 briefs a delegate to write tests that construct
`URLSession`s, and that brief tells the delegate not to run `coverage.sh` (memory). So the delegate
would have authored a violation of a rule it had no way to be told about, and the manager would
have found it later. The gate was in a list the delegate never runs.

## 5am. Use the session convention the repo already has (2026-09-06, leg 21)

`OPDSClient` already accepted a session. The server screens still constructed seven clients of
their own. Hosting the browser in a real window ran its `.task` against the shared session, and
the hermetic guard killed the test before there was a screen to assert against. The seam is now
an inherited client factory whose shipping default still evaluates `OPDSClient()` per operation.
Catalog navigation and detail destinations inherit the override.

The first pass kept the async work inside the view structs and exposed closures through a
DEBUG-only `OPDSViewTestAccess`. That was defensible, and its tests distinguished rendered changes
from physical taps, but it invented a permanent test bridge for a problem this repo already solves.
`ReaderSession` and `RSVPPresentationSession` are the convention: observable production sessions,
owned by the view through State, with optional session injection for tests.

The continuation follows that convention. `BrowseServerSession`, `ServerEditSession` and
`RemoteBookDetailSession` own the actual mutable state and operations. Views supply the environment
client factory, model context and presentation callbacks. The DEBUG bridge and every hook it needed
are deleted. Tests drive the same sessions directly and read their state without closures captured
from view structs that SwiftUI can recreate. The views are still hosted in real windows: feed and
cover tasks, pagination-row tasks, search submission and observation-driven rendering still execute.

The assertions pair pixel signatures with effects that pixels cannot establish: exact requests,
returned titles, persisted last-use timestamps, saved server values, imported book text and the
completion callback. Search submission goes through the installed search field's registered
UIControl submit action into SwiftUI's `onSubmit`. This is not a claim that every tap, navigation
gesture or modal dismissal was driven. Those are separate claims.

**The mock is a script, not a permanent answer.** Pagination and cover requests can overlap. Each
new mock session has its own finite script, matching exact URLs and consuming repeated URLs in
order. Held replies make loading assertions deterministic. Unknown URLs and exhausted queues hit
the same fatal guard as an absent single-shot stub. Separate crash controls exercise both failures.
The old single-shot API remains available for existing suites.

Two first-pass choices were also reversed. The fixture now declares a reserved `.invalid` address
in the test tree, so the documented plain test command needs no environment setup. The coverage
script is unchanged, and the environment helper is deleted. A non-routable fixture is not a secret
and is not a reason to touch a gate. The guard again includes the blocked URL: that is the useful
diagnostic, and the live integration target does not contain this hermetic bundle's bootstrap.

**A fixture can be wrong even when its name looks obvious.** A bare word used as an invalid URL
was normalized by the form into an HTTPS URL. The missing-stub guard caught the mistaken premise;
the fixture now uses a malformed URL. Weakening the guard would have concealed a bad test.

The first pass also exposed two silent no-ops worth retaining as lessons. Omitting `()` from a
Swift Testing method selector reported `TEST SUCCEEDED` with zero tests; that run was rejected.
And the installed SwiftUI search coordinator did not implement either optional delegate submit
callback. Calling one did nothing. The test requires a registered UIControl submit action and then
observes its request and displayed results. Returning without an error does not prove an event was
handled. The previous bridge's actor-thunk and immediate-`#require`-invocation compiler problems
are historical now; removing the bridge removes the need to maintain its workaround surface.

No coverage floor is changed on a focused run. The manager's combined lanes are the evidence for
that ratchet. Navigation gestures, modal dismissal and the browser's import toast remain outside
this suite's claims, as do real credentials and server access. Generic catches already wrapped by
`OPDSClient` into `OPDSError` remain uncovered rather than reached with an impossible fake error.

Observed on the continuation’s focused iOS 26.5 run: **15 tests passed**. The four views measured
92.70%, 97.11%, 98.67% and 100.00% respectively (browse, editor, detail, row); the three sessions
measured 95.65%, 95.41% and 98.08%. Both missing-stub crash controls failed at the intended guard,
and all honesty gates passed. These are focused-run figures, not the combined attributable result.

## 5an. The X8 is trusted again, and a lane that failed for a reason nobody wrote down (2026-09-06)

Two infrastructure findings from verifying leg 21, both worth keeping because both were invisible
in exactly the way this ledger keeps cataloguing.

### The volume constraint expired and one of our own lanes had been saying so all along

§5z routed `Scripts/coverage.sh` DerivedData to the boot volume because xcodebuild hung on the
Crucial X8: 23m25s elapsed for 6.89s CPU and ZERO tests, against `** TEST SUCCEEDED **` on boot,
same repo and commit, one variable changed. That fallback was deliberate, stated out loud, and
explicitly temporary — "Revert to dd-lease once the volume is trusted."

Retested today with DerivedData back on the X8: **exit 0 in 115s, 345 iOS + 70 watchOS tests
executed.** 415 executed tests is the unambiguous negative of a stalled directory walk. Reverted.

Honest caveat kept with the claim: that dd-lease slot was warm (581 MB cached, and X8 content
survived the reboot), so 115s is not evidence the volume is *fast* from cold. It is evidence the
volume does not *hang*, which is the only thing the fallback was protecting against — a warm cache
cannot manufacture 415 executed tests out of a directory walk that never returns.

The part worth being embarrassed about: **`Scripts/ui-lanes.sh` never carried this fallback.** It
has taken its DerivedData from `dd-lease` on the X8 the entire time, and it kept passing — including
twice today. So for two days the repo contained a lane that contradicted the constraint the other
lane was routed around, and nobody treated the asymmetry as evidence. §5z's own lesson was "what is
constant across all my failing runs *because a rule says it should be?*" The mirror of that question
is the one that was missed here: **what is already succeeding, in this same repo, under the exact
condition I have declared broken?**

### "Unable to find a device matching the provided destination specifier" meant a disk image

The UI lane then failed with that error, and the available-destinations list contained placeholders
and real hardware but not one concrete simulator. `xcrun simctl list devices` showed every runtime
section present — iOS 18.0, 26.2, 26.5, tvOS 26.5, watchOS 26.5 — and **zero devices under any of
them**.

Nothing had been deleted. There had been a power outage; the Mac cold-booted, and the simulator
device store lives on a disk image that did not remount. `sim-lease create` diagnosed and fixed it
in one line (`SimDevices image not mounted — running simdevices-mount`), and the same lane then
passed 5 + 4.

Three things this earns:

* **The error names the wrong subject.** It reads as a bad destination string, so the instinct is to
  edit the destination — a real change, to a correct lane, fixing nothing.
* **The usual wedged-CoreSimulator preflight is blind to it.** `simctl list devicetypes` answers
  normally while the device set is empty. Check for devices, not device *types*.
* **A lane passing earlier in the same session proves nothing.** `coverage.sh` ran 415 tests at
  16:35; the UI lane hit this at 18:23. Nothing announces the unmount.

Practical consequence, and it is the standing rule anyway: take simulators from
`sim-lease create --project speedread`, which mounts the image if needed and hands back a UDID, so
the lane gets `id=<udid>` instead of a `name=` that may match nothing.

## 5ao. The last five files need claims, not visitors (2026-09-06)

The shelf row and book spine already had coverage percentages. Neither had a test making a claim
about it: the host app happened to draw them on launch. The watch settings sheet, RSVP composition
and app root had no direct contracts at all. A file becoming attributable is not the accomplishment;
what matters is what can now fail if that file regresses.

The shelf tests measure both size classes: spine width, length-dependent height and its cap; the
bottom-only started marker; rendered author, title and theme changes; and content above a plank
whose pixels stay the same when books are added. An empty regular shelf retains its bay and rails.
The compact empty shelf retains only its plank. These are assertions on the actual rendered views,
not on a second implementation of their layout math. No production shelf code needed changing.

The settings sheet needed a small boundary around the controls. Its root supplies the same rows to
its List and to a render probe; the chapter destination forwards the visible word index and the
selection closure. A chapter boundary moves the rendered checkmark on exactly the affected rows.
The crown writes a snapping binding; Done applies that draft to the engine and AppStorage. Tests
hold an isolated defaults suite and prove that changing the draft changes the displayed number
without committing either the engine or defaults, then prove Done persists the snapped value.
The defaults helper and raster probe are symlinks across the two test trees, not parallel copies.

RSVP composition now takes its service, session and presentation bindings explicitly underneath
the environment-owning wrapper. Tests follow the same callback methods used by the surface,
sheet and lifecycle modifiers into a temporary library file and a recording connectivity session.
Chapter selection and crown browsing stay local; restore resolves the latest phone position;
playback commits go out; missing-book actions do neither. Rendering checks distinguish the loaded
word, selected chapter and playing surface. Calling a callback is evidence for that callback's
consequences, not evidence that a finger or Digital Crown delivered it.

The app-root claim was worth making, but not because an App can be instantiated. Library appearance
loads the injected store and activates its session. The direct RSVP fixture must do neither, or
loading the reader's saved library would overwrite the fixture before it can be used. Fixture
preparation also leaves ordinary launches alone and never writes fixture data to disk. That is a
composition contract with a real consequence. Fixture preparation remains inside `#if DEBUG`.

The first watch run exposed a trap in the probe itself: ImageRenderer is not a passive screenshot.
It delivers onAppear, which reloaded a playing RSVP session and reset an edited speed draft. Tests
now render the same controls beneath their lifecycle modifiers when comparing mutable states, and
separately observe renderer-delivered appearance for initial speed and app-root activation. A
NavigationStack cannot be flattened by this renderer; its placeholder pixels are not a rendering
claim. The chapter labels also need the watch's dark color scheme in the probe, or their default
text disappears against the test's black background.

One boundary deserves precision: fixture *preparation* does not write the library. Presenting RSVP
subsequently runs its ordinary crown-position persistence path, even for a fixture. The app-root
test observes that write in its temporary store as evidence that the injected service reached the
RSVP environment. Calling the whole path disk-free would have been a false claim.

OBSERVED: the focused iOS suite executed **3 passing tests**; the final focused watch run executed
**9 passing tests in 2 suites**; every honesty gate passed. The first iOS build's initialization
error, the first watch runner's launch failure (zero tests), and the failed lifecycle-contaminated
probes are retained beside the passing logs and xcresults under the durable leg evidence directory.
ASSUMED, not claimed here: physical crown delivery, navigation pushes, sheet dismissal, and normal
system-driven lifecycle timing. Renderer-delivered appearance is observed; it does not turn the
remaining platform-owned links into observed end-to-end interactions. Neither full lane script was run, and
neither the coverage floor nor the recorded combined percentage was changed. The manager's combined
run remains the evidence for any ratchet.

## 5ap. A test written to cover a branch found the branch was dead (2026-09-06, leg 23)

Leg 23 was the first *depth* leg: every shipping file was already named by a test, so the work was
raising coverage on files already counted. Its brief carried a different warning from the naming
legs — their trap was the denominator, this one's is that **a test which executes a line without
asserting anything raises the number and protects nothing.** The instruction was: for every test,
name a mutation it would catch, or do not write it.

That instruction is what produced the finding.

### The bug

A test was written to cover `ReaderView.readingEstimate`'s `"…% · finished"` branch. It failed:

```
(ReaderView.readingEstimate(book: longBook, lastWPM: 250) → "83% · <1 min left at 250 WPM")
    == "100% · finished"
```

The branch fires when `remainingWords == 0`, i.e. `lastReadWordIndex == wordCount`. There are
exactly two writers of `book.lastReadWordIndex`, and **both cap at `wordCount - 1`**:

* `ReadingPositionCoordinator.clampedIndex` — `min(max(0, index), wordCount - 1)`
* `WatchSyncService` — `lastValidIndex = max(0, book.wordCount - 1)`

So `book.progress` (`lastReadWordIndex / wordCount`) can never reach 1.0, the `"finished"` branch is
unreachable in the shipping app, and **a reader who finishes a book sees `"99% · <1 min left"`
forever.** `RSVPEngine` solves exactly this correctly — `if didFinish { return 1.0 }`, a flag kept
separate from `currentIndex` — but that flag is transient and never persisted to `Book`. The engine
knows you finished; the model never records it.

The operator's ruling: persist `finishedAt: Date?` on `Book`, set when the engine finishes and the
position commits, and have `progress` and `readingEstimate` honour it. Correct semantics, since
"reached the last word" and "finished the book" stay distinct, and SwiftData takes a new optional
property by lightweight migration. That fix is its own leg; this one records the finding.

### What the test does now, and why it was not simply deleted

The easy repair was to change the expectation to `"83% · <1 min left"`. That would have gone green
while **silently abandoning the branch the test existed to cover** — the exact failure this mission
keeps cataloguing, arriving this time disguised as a fix. What is committed instead asserts both
halves: the branch itself, driven by setting the state directly, and the fact that no commit path
can produce that state. The second assertion fails the day the clamp changes, which is precisely
when the display needs revisiting.

### Two process notes, both mine

**A resume without `-m` silently switches model.** `codex exec resume` takes the config default, not
the thread's recorded model. The substituted model then hit *its* usage limit and the turn died, so
the visible symptom was "resume failed on a quota" — which sends you to look at quota rather than at
the flag you forgot. Codex does warn, but as an `item.completed` event of `type: "error"` inside the
JSONL, never on stderr. Grep the JSONL for `"type":"error"` after every run.

**The honesty gates cannot catch a build failure.** They are static, and they passed cleanly on work
that did not compile — `XCTUnwrap` and XCTest's `file:`/`line:` parameters used inside Swift Testing
suites. Only running the lane finds that. A failed turn is truncated output, not a result, and no
amount of static checking substitutes for executing it.

And one of my own oracle errors, recorded because it is the third of this shape: I wrote
`ReaderSession.clampedIndex` into a test after reading the function body without noticing it is
declared on `ReadingPositionCoordinator`. Reading a definition is not the same as reading which type
owns it.

## 5aq. A book can be finished (2026-09-06, leg 24)

The bug 5ap found, fixed. `Book` gains `finishedAt: Date?`; `progress` returns 1.0 when it is set;
`ReadingPositionCoordinator.commit` gains a `didFinish` parameter and writes

```swift
book.finishedAt = didFinish && wordCount > 0 && clamped == wordCount - 1
    ? (book.finishedAt ?? now) : nil
```

Three properties are packed into that one line, and each corresponds to a way the obvious
implementation goes wrong:

* **`didFinish && clamped == wordCount - 1`** — reaching the last word is not finishing it. Tapping
  the final word to jump there must not complete a book, and `unopenedAndFinalWordJumpRemainUnfinished`
  holds that.
* **`book.finishedAt ?? now`** — re-finishing keeps the ORIGINAL completion date rather than
  overwriting it. Completion is an event that happened once.
* **the `: nil` branch** — *any* non-finishing commit clears completion. This is the re-read case,
  and it is the reason the naive "set a flag, return 1.0 forever" version is wrong: it makes every
  subsequent re-read display as complete. `rereadingClearsCompletionButBrowsingDoesNot` pins both
  halves — that committing a middle position clears it, and that merely *browsing* does not, since
  browsing has never committed a reading position.

`RSVPEngine.play()` now clears `didFinish`, so a replay must reach the end again before it can
re-complete. `WatchSyncService` clears `finishedAt` when it accepts a watch position, because
reading on the watch is the start of a re-read on the phone.

### The migration fixture is real, not simulated

`SpeedReadTests/Fixtures/PreCompletion.store` was generated **by the original production schema**,
before `finishedAt` existed, and its `ZBOOK` columns were inspected to confirm no `ZFINISHEDAT`
column is present. `preCompletionLibraryMigratesWithoutLosingContent` opens that store with the new
model. A migration test that builds its "old" store with the *new* schema tests nothing, which is
the same class of error as
[[fixtures must be sampled, not authored]] — recorded in this ledger at §5ad. The generator source
is kept in the evidence directory; it was removed from the test tree after producing the immutable
input, not removed to make a failure go away.

### Watch parity: deliberately not done, and why

`WatchBook`, the watch library JSON and `PositionPayload` carry no completion concept. Adding an
isolated `finishedAt` on the watch without transport and reconciliation would produce a field that
looks supported and silently never syncs — worse than its absence. What IS implemented and tested is
the direction that matters for correctness today: the phone accepting a watch position clears phone
completion. Full watch parity is a transport change and belongs in its own leg.

### Process note: a green run that never happened

The delegate was killed by the harness low-memory guard *during* its green verification —
`green.log` ends `** BUILD INTERRUPTED **`. Its red evidence was intact and unambiguous (exit 65 on
five separate runs), but "the implementation is written and the gates pass" is not the same claim as
"the tests pass", and the honesty gates cannot tell those apart because they are static. The manager
ran the focused suite (8 tests, `** TEST SUCCEEDED **`) and then both lanes.

Worth recording in the delegate's favour: it caught a vacuous selector itself. `red-natural.exit`
was **0** having matched zero tests, and rather than bank a green it wrote
"It is NOT passing evidence" and re-ran the whole suite. That is the §5ao trap, found and refused by
the same delegate that first recorded it.

## 5ar. EPUB corruption and watch reconciliation depth (2026-09-06, leg 25)

**OBSERVED: implementation is dirty and uncommitted; final runtime verification is blocked by
simulator health. This entry is not a claim that the leg's done condition passed.** The focused
baseline ran 46 tests successfully and reproduced EPUBExtractor **673/788 (85.41%)** and the iOS
WatchSyncService **366/428 (85.51%)** exactly. The expanded run compiled and executed 59 tests;
its measurements were **721/788 (91.50%)** and **377/428 (88.08%)**, respectively. That run failed
only eight parameter cases sharing a mistaken test expectation: the sampled `mimetype` has no
trailing newline. The expectation was corrected against Python `zipfile` inspection. Later
navigation/descriptor/chapter-metadata additions have no completed runtime result yet; their
coverage must not be inferred from these intermediate numbers.

**OBSERVED: fixture provenance.** EPUB tests read the committed
`SampleBooks/TheYellowWallpaper.epub` from the app bundle. Binary cases mutate that archive's
central/local records, or truncate it at an observed record boundary. XML cases mutate its
container, OPF and navigation; the existing stored-ZIP helper only repackages sampled contents.
The NCX and EPUB3 navigation are both present in that sample. No authored document is presented
as a real EPUB, no new dependency or copied cross-tree helper was added.

**OBSERVED: test intent and mutation contracts.** These are assertions about the new tests'
source; mutation operators below were identified by inspection, not run as mutation campaigns.

| Tests (existing suite extended) | Intent / driven path | Mutation the assertions catch |
| --- | --- | --- |
| EPUB `sampledArchiveRejectsCorruptDirectory` | Reject disk/count/ZIP64/bounds/signature/encryption/method/CRC/size/UTF-8 corruption, both unzip and public extraction | Accept a corrupted directory, or fall back to valid local headers after its rejection |
| EPUB `sampledLocalHeaderRejectsCorruption` | Exact sampled mimetype control, then reject corrupt local header or unknown-size descriptor | Drop local encryption, bounds, CRC or descriptor-position checks |
| EPUB `sampledPackageReportsSpecificFailure` | Missing/malformed container or OPF, empty/unresolved spine, malformed/escaping/root path | Return partial text, ignore malformed XML, or collapse the specified parser diagnostic into a ZIP error |
| EPUB `sampledArchiveWithoutDirectoryPreservesEveryEntry` | All 12 sampled entries survive local-header fallback | Skip a local entry or stop fallback scanning early |
| EPUB `sampledNavigationUsesNCXOrFallsBackWithoutChangingText` | Sampled NCX, invalid/missing navigation fallback, missing targets/fragments, whole-document links, duplicate marks; text stays 50,913 characters and byte-equal | Disable NCX, retain a missing anchor, forget heading fallback, duplicate a mark, or alter extracted text while discovering chapters |
| EPUB `sampledDuplicateEntryIsRejectedWithAndWithoutDirectory` | Reject duplicate names on both ZIP paths | Remove `updateValue == nil` uniqueness check |
| EPUB `corruptDeflateRejectsEmptyAndInvalidCompressedBytes` | Reject stored bytes relabeled as deflate, including empty compressed input | Treat inflation failure as valid content |
| EPUB `localHeaderCurrentlyIgnoresRequiredDescriptorIntegrity` | Pin known-bad acceptance of missing/contradictory descriptors | Adding correct descriptor validation intentionally breaks characterization |
| Sync `inactiveBookSendFailsWithoutEnqueuingDelivery` | Inactive transport reports failure without message/file enqueue | Remove activation guard or enqueue before checking it |
| Sync `dismissedOfferCannotMoveOrReopenBook`, `deletedBookInvalidatesPendingOffer` | Reject dismissed/deleted-book acceptance; retain completion or clear invalid pending offer | Ignore pending-offer equality, resurrect a deleted book, or leave deleted offer pending |
| Sync `localReadingAtOrAfterOfferInvalidatesIt` | Equal and newer phone timestamps reject old offers without changing position/completion | Change strict `>` reconciliation to `>=`, or mutate the book before rejection |
| Sync `replacementOfferRejectsOldValueAndPersistsAcceptedPosition` | Reject old offer identity; accept replacement; read markers/date from a separate model context | Compare only book ID, omit save, or omit accepted marker writes |
| Sync `unconfiguredAndUnknownBookPositionsDoNotCreateOffers` | Missing context/book is inert | Create an offer without a corresponding stored book |
| Sync `emptyBookOfferFormattingHasNoDivisionByZero` | Zero-word display and stable book identity | Divide by zero or use zero-based displayed word number |
| Sync two known-bug characterizations | Error acknowledgment and out-of-order pending offer | Correcting either defect intentionally breaks its characterization |
| WatchSyncLogic `malformedChapterMetadataRejectsEntireBook` | Reject eight malformed chapter shapes for inline/file decoding; allow last-word boundary | Silently discard corrupt chapters, accept index == count, or reject index == count - 1 |

**OBSERVED: shipping seam.** `WatchSyncService.applyIncomingPosition` changes from private to
internal, retaining `@MainActor` and its unchanged body. The production delegate already calls
it. This gives deterministic reconciliation tests without WCSession singleton access or timing
polls. No debug-only implementation was introduced and no production bug was fixed.

**Bugs found, separately:**

1. **OBSERVED in the expanded runtime: rejection is reported as successful delivery.**
   `sendBook` ignores its reply dictionary and sets `.sent(title)` even for `status: error`.
   Smallest service reproduction: an activated/reachable injected connection returns that reply;
   sending a negative-word-count payload (which the receiver decoder demonstrably rejects)
   still yields `.sent("Rejected")`, with no fallback. **ASSUMED user impact:** a rejected book
   can appear successfully sent. The fixture demonstrates the service chain, not a physical
   watch rejecting a book imported through the UI.
2. **OBSERVED in the expanded runtime: a pending position can regress.** Reconciliation compares
   incoming time only with the stored book, ignoring the pending offer's timestamp. Smallest
   reproduction: stored index/date `20/100`; incoming `80/300`, then `60/200`; pending changes
   to `60/200` and acceptance moves the book to 60 (furthest remains 80). **ASSUMED user impact:**
   delayed/out-of-order contexts could offer an older watch position. Such transport ordering
   was injected; physical WatchConnectivity ordering was not observed.
3. **OBSERVED in source and a macOS production-source probe: known-size local records do not
   validate data descriptors.** In local-header fallback, setting bit 3 with nonzero header sizes
   only computes a 12/16-byte skip; descriptor existence, CRC and sizes are never checked.
   Smallest fixture: the sampled first 58-byte mimetype local record, bit 3 set, followed by
   nothing, twelve zero bytes, or signature plus twelve zero bytes. All three were accepted by
   the unchanged production `unzipEntries` compiled for macOS. The standalone probe has only
   compile-time model contracts; its tokenizer stub traps if called. Its log records three
   successful exact-entry assertions. The iOS characterization tests still await execution. **ASSUMED user impact:** a truncated/corrupt local-header-only EPUB can
   be accepted if its local payload checks pass. This does not establish acceptance of a
   corrupt central-directory archive.

**OBSERVED: deliberately not covered.** Real WCSession file completion/receive callbacks,
unsupported-device activation, filesystem write failure, SwiftData save failure and delayed
status-reset timing remain untested by this leg. Simulating OS-only objects or adding broad
I/O/clock seams solely for coverage would expand the change beyond the identified logic.
The EPUB tests do not force allocation/base-address failures, Foundation regex/range failures,
or every encoding/descriptor variant. No public-API unreachable-branch proof was established;
these are omissions, not claimed coverage or claims of unreachable code. Watch completion
parity remains deliberately absent: WatchBook, its JSON and PositionPayload still carry no
completion concept. No watchOS test-tree changes were made.

**OBSERVED: evidence and commands.** Incremental state, runner source, complete logs, xccov JSON,
preflight output and notification receipts are in `~/Dispatcher/briefs/leg25-evidence/`.
Result bundles are on the external volume under `agent-artifacts/leg25/`.
`run-focused.sh baseline` uses `xcodebuild test`, scheme SpeedRead, plan Hermetic, all three
`-only-testing:SpeedReadTests/{EPUBExtractorTests,WatchSyncServiceTests,WatchSyncLogicTests}`
selectors, a simulator from `sim-lease create --project speedread`, leased DerivedData,
`-parallel-testing-enabled NO` and code coverage enabled. Neither coverage.sh nor ui-lanes.sh
was run. The floor and combined measurement were not edited.

The final attempt reached app validation and stopped producing output before tests started.
A new `simctl list devicetypes` probe produced zero bytes and exceeded its 12-second deadline;
the initial preflight had returned device types. Own xcodebuild was interrupted, yielding
`** TEST INTERRUPTED **`. No global simulator resets/reboots or foreign-process kills were
attempted. The operator notification was accepted by both ntfy hosts (HTTP 200).
**OBSERVED: honesty gates pass; final focused suite success and final coverage remain pending.**

**OBSERVED supplementary probe:** `DescriptorProbe.swift` in the evidence directory compiles
with the actual production EPUBExtractor.swift using the Xcode toolchain, explicit macOS SDK
and arm64 macOS 15 target. `descriptor-probe.log` records acceptance of all three malformed
descriptors. This establishes runtime behavior on macOS, not iOS test success or coverage.
DerivedData was released; simulator release itself exceeded 15 seconds with no output, so
cleanup is unconfirmed and its leased UDID remains recorded for host recovery.


## 5as. Correct rejected sends, offer ordering, ZIP descriptors, and watch-local completion (2026-09-06, leg 26)

**OBSERVED: scope and implementation.** The three leg-25 characterization tests were retained,
renamed to describe corrected behavior, and their assertions reversed only after executing them
against the production fixes. No third-party dependency, coverage floor, gate exemption, transport
field, or `finishedAt` parity was added. This leg leaves its changes uncommitted for manager review.

- **OBSERVED, rejected sends:** `WatchSyncService.sendBook` accepts only a string `status` equal to
  `ok`. Explicit rejection, empty reply dictionaries, absent status, wrong-type status and unknown
  status produce `.failed("Apple Watch did not accept the book.")`; they do not enqueue a file.
  The existing transport-error fallback remains. The reply callback's dictionary is nonoptional;
  a callback that never arrives is not covered by this change and no reply timeout was added.
- **OBSERVED, pending positions:** `WatchSyncLogic.shouldOfferWatchPosition` additionally rejects
  timestamps older than or equal to the same book's pending offer. The service passes the pending
  date only for a matching book ID. Stored-book timestamp and material-distance reconciliation
  remain in place, and furthest-read merging still precedes offer selection.
- **OBSERVED, ZIP descriptors:** local-header fallback now bounds the promised descriptor and
  validates its CRC, compressed size and uncompressed size against the values used to extract and
  validate the payload. Both signed and unsigned known-size descriptors are checked. Tests mutate
  the actual sampled mimetype record, accept valid descriptors, reject each corrupt field and
  every one-to-twelve-byte truncation. All three SampleBooks EPUBs extract identically with and
  without their central directories, including chapter and complete entry-map comparisons.
- **OBSERVED, watch-local completion:** `WatchBook.hasFinishedLocally` is a persisted Bool, defaulting
  to false when decoding legacy JSON. Actual `RSVPEngine.didFinish` is captured in the local session
  commit, observed by the view, and persisted after committing its last-word position. Completion
  commits also survive dismissal before the observation callback. Completed books report progress
  1; reaching the last word alone does not complete a book. Browsing preserves completion; committing
  an earlier position clears it. A received phone position at the last index remains unfinished.
  This Bool and local commit metadata are never added to `PositionPayload`.

**OBSERVED: required failing characterizations, before updating assertions.**
`characterization-red` ran 64 tests in 3 suites and failed with exactly 7 issues:

```text
rejectedBookReplyIsCurrentlyMisreportedAsSent:
Expectation failed: (service.sendState → .failed("Apple Watch did not accept the book. Please try sending it again.")) == .sent("Rejected")
pendingOfferCurrentlyRegressesWhenContextsArriveOutOfOrder:
Expectation failed: (offer.wordIndex → 80) == 60
Expectation failed: (offer.timestamp → 1970-01-01 00:05:00 +0000) == (Date(timeIntervalSince1970: 200) → 1970-01-01 00:03:20 +0000)
Expectation failed: (book.lastReadWordIndex → 80) == 60
localHeaderCurrentlyIgnoresRequiredDescriptorIntegrity:
kind → "missing": Caught error: .invalidData
kind → "unsigned": Caught error: .invalidData
kind → "signed": Caught error: .invalidData
```

**OBSERVED: corrected passing forms.** `rejectedBookReplyFailsWithoutFileFallback` expects `.failed`
and zero files (the final failure copy removes the retry suggestion). The pending-offer test now
expects word 80, timestamp 300 and acceptance at word 80. `localHeaderValidatesRequiredDescriptorIntegrity`
expects `ExtractionError.invalidData` for all three original variants. The exact old failure output
and final passing output are preserved in the evidence directory.

**OBSERVED: watch red/green.** Before watch production changes, the real engine finished the sampled
eight-word Gutenberg heading, then the test failed with `finished.progress → 0.875`, detail percentage
`87`, and library text `"87% complete"`, each compared with completion (1, 100, `"100% complete"`).
The same test now passes both the observation-handler and immediate-dismissal paths, reloads the
store, and checks rereading and transport keys. Legacy decoding and phone-position noncompletion
assertions also pass. The text was sampled verbatim from TheYellowWallpaper.epub's `pg-header-heading`.

**OBSERVED: commands and final results.** Reproducible shell runners, raw logs, exit codes, leases,
and running STATE.md are in `~/Dispatcher/briefs/leg26-evidence/`. Result bundles are on the external
volume under `agent-artifacts/leg26/`.

```text
bash ~/Dispatcher/briefs/leg26-evidence/run-focused.sh samples-final
✔ Test run with 68 tests in 3 suites passed after 22.617 seconds.
** TEST SUCCEEDED **
bash ~/Dispatcher/briefs/leg26-evidence/run-watch.sh watch-final
✔ Test run with 50 tests in 8 suites passed after 0.467 seconds.
** TEST SUCCEEDED **
Scripts/honesty-gates.sh
PASS: all honesty gates
```

**OBSERVED: selectors and setup.** The iOS runner uses `xcodebuild test`, scheme SpeedRead, plan
Hermetic, with `-only-testing:SpeedReadTests/EPUBExtractorTests`, `WatchSyncServiceTests`, and
`WatchSyncLogicTests` (each fully target-qualified). The watch runner uses scheme
`SpeedReadWatch Watch App`, plan WatchHermetic, and target-qualified selectors for
WatchReadingCompositionTests, WatchPositionModelTests, WatchRSVPSessionTests,
WatchPresentationCharacterizationTests, WatchLibraryTests, WatchSyncServiceCharacterizationTests,
WatchBookDetailPresentationTests, and WatchLibraryPresentationTests. Both use leased DerivedData,
explicit leased simulator IDs, `-parallel-testing-enabled NO`, and code coverage enabled.
Neither `Scripts/coverage.sh` nor `Scripts/ui-lanes.sh` was run.

**OBSERVED: infrastructure limitation and recovery.** The initial watch run compiled but executed
no tests because the simulator rejected launch with `Unknown application display identifier`.
An install probe found it Shutdown; bounded boot and install succeeded, after which the expected-red
and green watch tests executed. No simctl call exceeded its short bound. An early watch selector
named the test file instead of its two actual suite types; this was corrected for the final
50-test run. A concurrent manager commit changed the lane scripts; this agent did not edit them.

**OBSERVED verification boundary / ASSUMED unexercised links.** Tests observed the real engine
finishing, then invoked the view's composition callback or disappearance method directly, and
observed persistence plus presentation values. SwiftUI's automatic delivery of the `.onChange`
callback is source-inspected and compiled but ASSUMED at runtime in this leg. Physical paired
WatchConnectivity delivery and actual library/detail screen rendering at completion were not
exercised. No full UI or physical-device end-to-end claim is made. Cross-device completion remains
explicitly outside this leg.
