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

## 5b. Open finding — an empty test target in no plan (OBSERVED 2026-08-31)

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

## 12. Open finding — RSVP play/pause is unreachable by assistive technology

`RSVPView` has no accessible play/pause control. The only way to start or stop the stream is
tapping the word display, which is a bare `DragGesture(minimumDistance: 0)` (previously
`.onTapGesture` — equally invisible). VoiceOver, Voice Control, Switch Control and keyboard cannot
reach the **primary interaction of the app's flagship mode**. Not a regression from leg 2; a
pre-existing defect leg 2 walked past.

This sits directly against the *reasoning* behind CORPUS §4.5 ("tappable words are `Button`s —
Voice Control, focus and keyboard navigation depend on it"). The invariant is written for reader
words; the argument applies identically here. Roadmap I16–I19 already carry a11y work. Queue it.

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

### Still open, deliberately not patched

`crownValue` is written **only** in `.onAppear` and never follows the engine, so after playback the
first detent should snap the reader back to wherever they opened RSVP. Real, and *not* what the
operator reported. Not fixed standalone because it is precisely what `browseWordIndex` handles in
the three-marker design now under review — patching it twice would be churn. If that design is
rejected, this becomes its own red-first fix.

## 15. Watch settings + position model — DESIGN UNDER REVIEW, not started

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

Awaiting: approval of the design, and of one rename — "Go to Phone Position" →
"Back to where I was reading" (same number when synced; the local one also works with the phone in
another room and does not lie about what it does).

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

⚠️ **One spot is safe by invariant rather than by construction:** `continueFromWatch` reads
`furthestReadWordIndex` without migrating first. It cannot actually see a sentinel, because an offer
only exists if `applyIncomingPosition` already migrated that same book, and offers are in-memory so
cannot survive a restart. Consequence if the invariant ever broke is small (a `-1` max-merges
harmlessly), but the reasoning is non-local. Harden when next in that file.
