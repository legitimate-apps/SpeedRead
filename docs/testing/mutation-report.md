# Mutation gate report

Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.

Run 2026-08-31 20:48 · 22 mutations · 21 killed · 1 survived (1 of them expected) · 0 not counted · **0 unexpected**

Every verdict in this table was measured by this run.

| mutation | verdict | expected | measured | note |
|---|---|---|---|---|
| ORP: 2-5 char words pivot moves 1->2 | **KILLED** | KILLED | this run | suite failed, as it should |
| ORP: 6-9 char words pivot moves 2->3 | **KILLED** | KILLED | this run | suite failed, as it should |
| ORP: 10-13 char words pivot moves 3->4 | **KILLED** | KILLED | this run | suite failed, as it should |
| ORP: focus clamp off-by-one (OOB risk) | **SURVIVED** | SURVIVED | this run | suite still green — nothing pins this — EQUIVALENT MUTANT — not a test gap, and no test can close it. bucket(s) <= s-1 for every s >= 1, and leadingPunct + strippedLength <= count, so orpIndex <= count-1 always; the clamp never fires and both forms behave identically. Proven analytically (pure counting, so character-set independent) and empirically over 1,411,111 words — exhaustive to length 6 over an adversarial alphabet plus 300k random to length 40 — with zero counterexamples and a tightest slack of exactly 0. The clamp stays as cheap insurance; the invariant that makes it dead is what a test should pin. |
| WordTimer: long-word threshold 8->9 | **KILLED** | KILLED | this run | suite failed, as it should |
| WordTimer: long-word multiplier 1.3->1.6 | **KILLED** | KILLED | this run | suite failed, as it should |
| WordTimer: numeric multiplier 1.8->1.4 | **KILLED** | KILLED | this run | suite failed, as it should |
| WordTimer: sentence-end multiplier 2.0->1.9 | **KILLED** | KILLED | this run | suite failed, as it should |
| WordTimer: clause-end multiplier 1.5->1.4 | **KILLED** | KILLED | this run | suite failed, as it should |
| WordTimer: base delay constant | **KILLED** | KILLED | this run | suite failed, as it should |
| RSVP: WPM clamp upper bound 1500->1400 | **KILLED** | KILLED | this run | suite failed, as it should |
| WatchSync: staleness comparison > -> >= (equal-timestamp replay) | **KILLED** | KILLED | this run | suite failed, as it should |
| Book: progress denominator off-by-one | **KILLED** | KILLED | this run | suite failed, as it should |
| Book: hyphen tokenisation split character | **KILLED** | KILLED | this run | suite failed, as it should |
| OPDS: success status range widened to accept redirects | **KILLED** | KILLED | this run | suite failed, as it should |
| OPDS: insecure-HTTP gate inverted (security) | **KILLED** | KILLED | this run | suite failed, as it should |
| OPDS: DEFAULT ARGUMENT for session (tests always pass a mock) | **KILLED** | KILLED | this run | suite failed, as it should |
| Book: token-cache migration guard inverted | **KILLED** | KILLED | this run | suite failed, as it should |
| furthestRead: max-merge becomes MIN (high-water mark runs backwards) | **KILLED** | KILLED | this run | suite failed, as it should |
| commit throttle removed (every tick commits) | **KILLED** | KILLED | this run | suite failed, as it should |
| commit throttle comparison inverted | **KILLED** | KILLED | this run | suite failed, as it should |
| CrownSeek: direction un-inverted (the operator-reported bug returns) | **KILLED** | KILLED | this run | suite failed, as it should |
