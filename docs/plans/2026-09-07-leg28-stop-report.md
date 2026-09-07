# Leg 28 — negative position reachability stop

Historical checkpoint. The manager subsequently classified this as latent hazard I34, authorized consolidation, and required the original decoder boundary test to stay unchanged. See `2026-09-07-leg28-results.md` for the resumed outcome. The observations below describe the stopped run, not the final state.

OBSERVED: work stopped under the user's hard constraint 2 before changing production code.
The decoder is a boundary for the current shipping caller, but not for the internal service API.

## Trigger to effect

- OBSERVED — `SpeedRead/Connectivity/WatchSyncService.swift:142`: the typed
  `PositionPayload` initializer assigns a negative `wordIndex` unchanged.
- OBSERVED — `SpeedReadTests/WatchSyncServiceTests.swift:418`: the existing in-memory
  fixture directly calls `applyIncomingPosition` with index -1, local index 20, 100 words,
  and a timestamp newer than the local reading timestamp.
- OBSERVED — `SpeedRead/Connectivity/WatchSyncService.swift:609`: the upper-only clamp
  retains -1. At `:218`, the offer decision independently clamps to zero; the distance
  from local index 20 exceeds the material threshold, so the offer is created at `:625`.
- OBSERVED — `SpeedReadTests/WatchSyncServiceTests.swift:420`: the resulting offer's
  index is -1, and the assertion requiring zero fails on the simulator.
- OBSERVED — `SpeedReadTests/WatchSyncServiceTests.swift:400`: a separate test proves
  decoding rejects -1 and accepts zero. Its comment names deleting or tightening the guard
  as the mutations it protects against.
- OBSERVED — `SpeedRead/Connectivity/WatchSyncService.swift:596`: repository search found
  only this shipping caller of `applyIncomingPosition`; it is downstream of the decoder
  at `:568`. No shipping transport bypass was demonstrated.
- ASSUMED — whether internal API reachability merits a production bug classification is
  the manager's decision; this report does not claim a user can send a negative index
  through the current WatchConnectivity decoder.

## Commands and output

OBSERVED: the final execution used a simulator created by
`sim-lease create --project speedread-leg28 --purpose tests --owner-pid "$$"`
inside the same shell as the test command. DerivedData came from
`dd-lease path --project speedread --purpose tests`. Both leases were released.

```sh
xcodebuild test-without-building -project SpeedRead.xcodeproj -scheme SpeedRead \
  -destination "platform=iOS Simulator,id=$(cat /tmp/speedread-leg28/sim)" \
  -derivedDataPath "$(cat /tmp/speedread-leg28/dd)" \
  -parallel-testing-enabled NO \
  -only-testing:SpeedReadTests/WatchSyncServiceTests \
  -resultBundlePath /tmp/speedread-leg28/service.xcresult \
  > /tmp/speedread-leg28/service.log 2>&1
```

OBSERVED output, exit 65:

```text
✔ Test positionDecoderRejectsNegativeButAcceptsZero() passed after 0.001 seconds.
✘ Test directlyConstructedNegativePositionCannotProduceNegativeOffer() recorded an issue at WatchSyncServiceTests.swift:420:9: Expectation failed: (offer.wordIndex → -1) == 0
✘ Test run with 24 tests in 1 suite failed after 0.227 seconds with 1 issue.
```

OBSERVED: `xcrun xcresulttool get test-results summary --path
/tmp/speedread-leg28/service.xcresult` independently reports `totalTestCount: 24`,
`passedTests: 23`, `failedTests: 1`, `skippedTests: 0`.

OBSERVED: earlier attempts produced a test-host bootstrap failure (exit 65), a missing
destination (exit 70), and an empty selected run (exit 0, zero tests). None is counted
as boundary verification. Their artifacts remain in `/tmp/speedread-leg28/`.

OBSERVED command: `Scripts/honesty-gates.sh`, exit 0. Full output is in
`/tmp/speedread-leg28/honesty.log`; final output:

```text
PASS: executed-test parser control -- 12 checks, expected counts all matched
PASS: strip_comments self-test -- 9 cases, both directions asserted
PASS: is_debug_only self-test -- 9 cases, 4 positive / 5 negative
PASS: all honesty gates
```

## Deliverable state and tests not written

- OBSERVED — decoder boundary test completed at `SpeedReadTests/WatchSyncServiceTests.swift:400`.
- OBSERVED — failing reachability reproducer retained at `:414`, with its intended
  lower-bound mutation named. It is intentionally red, not an expected-failure exemption.
- OBSERVED — clamp consolidation withheld at `WatchSyncService.swift:609` under the
  explicit stop condition; no production source or Scripts file was edited.
- OBSERVED — per-call-site clamp tests and the remaining WatchSyncService coverage audit
  were not completed because the prerequisite reachability probe triggered the stop.
  No unexamined line has been classified as undeserving of a test.
- OBSERVED — SpineColor coverage tests were not written before the stop. The shared-source
  audit passed and reported SpineColor as single-source; its three alleged uncovered
  lines were not independently measured or classified.
- OBSERVED — `Scripts/coverage.sh 89` and `Scripts/ui-lanes.sh` were not run; combined
  ATTRIBUTABLE before/after is unmeasured. The user's 88.94% and 49-line starting values
  remain ASSUMED, not evidence from this run.
- OBSERVED — changes remain uncommitted for the manager's decision because the retained
  reproducer fails. The requested green done condition has not been met.
