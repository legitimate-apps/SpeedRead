#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: Scripts/coverage.sh <minimum-combined-attributable-coverage-percent>" >&2
  echo "Example: Scripts/coverage.sh 80" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

threshold="$1"
if [[ ! "$threshold" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] \
  || ! awk -v value="$threshold" 'BEGIN { exit !(value >= 0 && value <= 100) }'; then
  echo "error: threshold must be a number from 0 through 100" >&2
  exit 64
fi

for tool in xcodebuild xcrun awk sort mktemp python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' was not found" >&2
    exit 69
  fi
done

if [[ ! -x /usr/bin/jq ]]; then
  echo "error: /usr/bin/jq is required to read xccov's JSON report" >&2
  exit 69
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project="$repo_root/SpeedRead.xcodeproj"

# Runtime registration covers iOS shared/default sessions, while this source audit closes the
# custom-configuration hole and the watchOS global-registration no-op measured on watchOS 26.5.
python3 "$script_dir/network-isolation-audit.py" "$repo_root"

ios_destination="${SPEEDREAD_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
watch_destination="${SPEEDREAD_WATCH_DESTINATION:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest}"

# Ownership bookkeeping and the trap that gives it back, declared BEFORE anything is acquired.
# A trap installed after the leases exist leaves a window in which a lease is held by nobody.
leased_sims=()
leased_derived_data=""
work_dir=""

# What this run owns, as the union of two sources -- neither is sufficient alone.
#
# The shell array alone is not, because `sim-lease create` writes its lease file BEFORE this
# shell gets the udid back and can append it. A signal arriving in that window strands a
# freshly created simulator with nothing left to release it. MEASURED 2026-09-07: with the
# array fixed and only the array consulted, a SIGTERM control leaked 1 of 1 leases from
# coverage.sh (caught mid-create) while ui-lanes.sh passed -- same code, different timing.
#
# The query alone is not, because a lease this run adopted rather than created would not match.
#
# The query is keyed on owner_pid and nothing else that can collide. It was previously scoped by
# project + session + purpose + created-within-300s, and that BROKE A RELEASE-CANDIDATE CI RUN on
# 2026-09-07. On CI there is no CLAUDE_CODE_SESSION_ID, so every lane has session_id null and the
# same two purposes, and `concurrency: cancel-in-progress` guarantees that a cancelled run and the
# run superseding it start within seconds of each other. The cancelled run's cleanup matched the
# NEW run's freshly created leases and deleted its simulator mid-test: "No matching device ... in
# set". I had considered this exact collision when writing the window and argued it away as "the
# cancelled run is being cancelled anyway" -- which is backwards. The cancelled run is the one
# doing the deleting.
#
# owner_pid is recorded per lease by `sim-lease create --owner-pid "$$"` and is this shell's pid,
# so no other run can match it, on CI or anywhere else.
our_leased_sims() {
  {
    for leased_sim in ${leased_sims[@]+"${leased_sims[@]}"}; do
      [[ -n "$leased_sim" ]] && printf '%s\n' "$leased_sim"
    done
    sim-lease list --json 2>/dev/null | python3 -c '
import json, sys
owner = int(sys.argv[1])
try:
    leases = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for lease in leases:
    if lease.get("project") != "speedread": continue
    if lease.get("owner_pid") != owner: continue
    print(lease["udid"])
' "$$" 2>/dev/null || true
  } | sort -u
}

cleanup() {
  # An EXIT trap reports the status of ITS OWN last command unless told otherwise: on
  # 2026-09-06 the release loop's own non-zero return turned a fully green lane -- 385 + 80
  # tests, 91.37% -- into `exit 1`. Capture and re-return.
  #
  # That loop was returning non-zero because it was iterating an EMPTY array, and the array was
  # empty because the append happened in a subshell (see lease_sim). Preserving the exit status
  # is still right, but it was never the bug -- it was the bug's only visible symptom, and
  # fixing it silenced the one signal that something was wrong. If a container here is
  # unexpectedly empty, that is the finding, not the noise.
  local exit_status=$?
  if [[ -n "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
  if [[ -n "$leased_derived_data" ]]; then
    dd-lease release "$leased_derived_data" >/dev/null
  fi
  for leased_sim in $(our_leased_sims); do
    sim-lease release "$leased_sim" >/dev/null 2>&1 || true
  done
  return "$exit_status"
}
trap cleanup EXIT

# An EXIT trap does NOT run when the shell is killed by a signal, and ci.yml sets
# `concurrency: cancel-in-progress: true` -- so every superseded CI run was SIGTERMed while
# still holding its leases, leaving a booted simulator pair behind for the FULL 2h TTL, because
# sim-lease's reaper disposes a lease only when it is both expired AND owner-dead. Four such
# orphans were live on 2026-09-07 and were most of that day's simulator pile-up. Re-raising
# through `exit` runs the EXIT trap exactly once and keeps the conventional 128+signal status.
# Nothing can cover SIGKILL -- that is what the reaper is for.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Simulators come from sim-lease, so the reap path owns them. A `name=` destination makes
# xcodebuild boot whatever stock device matches, which is an OWNERLESS booted simulator: nothing
# releases it, and on 2026-09-06 that class left six `xpcproxy_sim` stubs stuck in exec, wedged
# every full-table `ps` on the machine for two hours, and cost the fleet a reboot. A leased device
# is reaped when its owner dies; a stock one is not. Explicit destinations still win, so CI and a
# manual run can both override.
# Prints a udid and NOTHING else. It deliberately does not record the lease itself: every call
# site is `udid="$(lease_sim ...)"`, and a command substitution is a SUBSHELL, so a
# `leased_sims+=(...)` performed in here mutated a copy that died with the subshell. That is not
# hypothetical -- it is why this project accumulated 22 simulator leases in one session while a
# cleanup trap that "released them" ran green every time. The tell was already on the table and
# I misread it: on 2026-09-07 the release loop returned 1 *on an empty array*, and I fixed the
# exit status instead of asking why the array was empty. Recording belongs to the parent shell.
lease_sim() {  # $1 = device name, $2 = purpose ; prints a udid. Does NOT boot, does NOT record.
  local device="$1" purpose="$2" udid lease_errors
  lease_errors="$(mktemp "${TMPDIR:-/tmp}/speedread-lease-err.XXXXXX")"
  # stderr goes to a FILE, never merged with 2>&1: sim-lease writes reap diagnostics there, and a
  # merged stream would let `tail -1` return a reap line instead of the udid.
  udid="$(sim-lease create --project speedread --owner-pid "$$" --device "$device" --purpose "$purpose" \
    --ttl-hours 2 2>"$lease_errors" | tail -1)"
  if [[ ! "$udid" =~ ^[0-9A-F-]{36}$ ]]; then
    # Say so LOUDLY. Failing here does not stop the lane -- it falls back to the stock `name=`
    # destination below, and xcodebuild then boots whatever matches, which is an OWNERLESS booted
    # simulator that no reaper owns. That class left six wedged xpcproxy_sim stubs, blocked every
    # full-table ps on the machine for two hours and cost the fleet a reboot on 2026-09-06. The
    # lanes also now require a sim-lease that accepts --owner-pid, so a rollback of that tool
    # lands exactly here; a rollback must announce itself rather than quietly recreating the
    # original failure.
    echo "warning: sim-lease create failed for '$device' (purpose $purpose)." >&2
    echo "         This lane falls back to a stock name= destination, i.e. an OWNERLESS booted" >&2
    echo "         simulator that nothing will reap. sim-lease said:" >&2
    sed 's/^/           /' "$lease_errors" >&2
    rm -f "$lease_errors"
    return 1
  fi
  rm -f "$lease_errors"
  printf '%s' "$udid"
}

# Booting is deferred to the lane that needs it, and the previous lane's simulator is shut down
# first. The two lanes below run SERIALLY, but leasing used to boot both up front -- so the iOS
# simulator sat booted through the entire watchOS lane, doing nothing, on a Mac whose MEASURED
# ceiling is about two booted simulators. Half the machine's capacity, held by a script that was
# not using it. With several sessions plus CI running these same two scripts, 2026-09-07 reached
# TEN booted simulators, 27.6 GB of swap and a one-minute load average of 964, and the harness
# began reaping background tasks fleet-wide. Boot before the lane, shut down after it: peak one
# simulator per script instead of two.
active_sim=""
activate_sim() {  # $1 = udid, or "" when the caller supplied its own destination
  local udid="${1:-}"
  if [[ "$active_sim" == "$udid" ]]; then
    return 0
  fi
  if [[ -n "$active_sim" ]]; then
    xcrun simctl shutdown "$active_sim" >/dev/null 2>&1 || true
    active_sim=""
  fi
  if [[ -z "$udid" ]]; then
    return 0
  fi
  # Boot here rather than letting xcodebuild do it. MEASURED 2026-09-07: a freshly created
  # watchOS device that xcodebuild boots itself is not ready for the UI test runner's install --
  # the lane dies with FBSOpenApplicationErrorDomain Code=4 "Unknown application display
  # identifier", deterministically, twice in a row. Pre-booting and waiting for bootstatus makes
  # the same lane pass 4/4. The unit lanes never showed it, because a hosted unit bundle installs
  # differently from an .xctrunner.
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  # Bounded, because `bootstatus -b` is a wait with no timeout of its own and it does not always
  # settle. MEASURED 2026-09-07, on a machine recovering from a 27 GB-swap incident: 4m31s on a
  # device that `simctl list` already reported as Booted, with the lane making no progress behind
  # it. A wait that can outlast the work it is preparing for has to be capped -- past the cap,
  # xcodebuild does its own waiting, so the failure mode degrades from "lane hangs" to "lane is
  # slower", and the warning says which happened instead of leaving a silent stall.
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &
  local waiter=$! waited=0
  while kill -0 "$waiter" 2>/dev/null && (( waited < 180 )); do
    sleep 2
    waited=$(( waited + 2 ))
  done
  if kill -0 "$waiter" 2>/dev/null; then
    kill "$waiter" 2>/dev/null || true
    echo "warning: bootstatus for $udid did not settle in ${waited}s; continuing anyway" >&2
  fi
  wait "$waiter" 2>/dev/null || true
  active_sim="$udid"
}

ios_udid=""
watch_udid=""
if command -v sim-lease >/dev/null 2>&1; then
  if [[ -z "${SPEEDREAD_IOS_DESTINATION:-}" ]]; then
    if ios_udid="$(lease_sim "iPhone 17 Pro" "tests")"; then
      leased_sims+=("$ios_udid")   # parent shell, not the subshell above
      ios_destination="platform=iOS Simulator,id=$ios_udid"
    fi
  fi
  if [[ -z "${SPEEDREAD_WATCH_DESTINATION:-}" ]]; then
    if watch_udid="$(lease_sim "Apple Watch Series 11 (46mm)" "tests-watch")"; then
      leased_sims+=("$watch_udid")   # parent shell, not the subshell above
      watch_destination="platform=watchOS Simulator,id=$watch_udid"
    fi
  fi
fi

derived_data_path="${SPEEDREAD_DERIVED_DATA_PATH:-}"
leased_derived_data=""
# Was routed to the boot volume 2026-09-04 because xcodebuild HUNG with DerivedData on the
# Crucial X8: 23m25s elapsed for 6.89s CPU and ZERO tests, against ** TEST SUCCEEDED ** on boot,
# same repo and commit, one variable changed (TDD-MISSION.md 5z). RETESTED 2026-09-06 and the
# hang is gone: exit 0 in 115s with 345 iOS + 70 watchOS tests executed on the X8. 415 executed
# tests is the unambiguous negative of a stalled directory walk, whatever the cache state.
# Scripts/ui-lanes.sh never carried this fallback and was passing on the X8 throughout, which
# was the corroborating signal nobody weighted at the time.
if [[ -z "$derived_data_path" ]] && command -v dd-lease >/dev/null 2>&1; then
  derived_data_path="$(dd-lease path --project speedread --purpose tests)"
  leased_derived_data="$derived_data_path"
fi

package_cache_path="${SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH:-}"
if [[ -z "$package_cache_path" ]] && command -v dd-lease >/dev/null 2>&1; then
  package_cache_path="$(dd-lease spm-path)"
fi

# Where a FAILING lane's evidence is kept. The .xcresult bundle names the failing test and is
# written by xcodebuild anyway -- and until now it lived in work_dir and was deleted by the
# cleanup trap on failure as well as on success. So a red run paid up to 600s for a sysdiagnose
# nobody reads (see -collect-test-diagnostics above) and then threw away the cheap artefact that
# actually explains the failure. Keep the useful one, skip the expensive one.
#
# Never falls back to the boot volume: this Mac has repeatedly hit "disk full" and .xcresult
# bundles are tens of megabytes. No external drive means no artefact plus a warning, which is a
# worse debugging experience and a better failure mode.
failure_artifact_dir="${SPEEDREAD_FAILURE_ARTIFACT_DIR:-}"
if [[ -z "$failure_artifact_dir" && -d "/Volumes/Crucial X8" ]]; then
  failure_artifact_dir="/Volumes/Crucial X8/agent-artifacts/speedread-lane-failures"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/speedread-coverage.XXXXXX")"

ios_result="$work_dir/SpeedRead-Hermetic.xcresult"
watch_result="$work_dir/SpeedRead-Watch-Hermetic.xcresult"
ios_log="$work_dir/ios-tests.log"
watch_log="$work_dir/watch-tests.log"

common_build_arguments=(
  -project "$project"
  -parallel-testing-enabled NO
  # xcodebuild defaults to `-collect-test-diagnostics on-failure`, which runs
  # `simctl diagnose --timeout=600` on EVERY red run. OBSERVED on this machine: it presents
  # as a hang with no output, indistinguishable from a wedged CoreSimulator.
  #
  # This is a GATE, so going red is its job, not an edge case -- and it runs two lanes, so a
  # bad push can buy up to 20 minutes of sysdiagnose against a 40-minute CI timeout. That
  # turns a clear test failure into an ambiguous timeout, which is the real harm.
  #
  # Deliberately NOT a universal rule: a peer project keeps the collector ON in CI on the
  # reasonable grounds that a failure you cannot reproduce locally is exactly when you want
  # diagnostics. What decides it here is that NOTHING CONSUMES THE OUTPUT -- this workflow has
  # no artifact upload, so the collector writes a sysdiagnose into the runner's work dir that
  # no human will ever open. If we ever want CI diagnostics, the fix is to upload them and pay
  # the cost on purpose, not to re-enable a collector nobody reads.
  -collect-test-diagnostics never
)
if [[ -n "$derived_data_path" ]]; then
  common_build_arguments+=( -derivedDataPath "$derived_data_path" )
fi
if [[ -n "$package_cache_path" ]]; then
  common_build_arguments+=( -clonedSourcePackagesDirPath "$package_cache_path" )
fi

keep_artifact() {
  local src="$1" dest="$2" what="$3"
  if [[ -e "$src" ]]; then
    cp -R "$src" "$dest/" 2>/dev/null \
      || echo "warning: could not copy $what from $src" >&2
  else
    # The `else` is the whole point. A bare `if [ -e ] ; then cp; fi` produces IDENTICAL output
    # -- none -- for "there was genuinely nothing to preserve" and "I built the wrong path", so a
    # preservation step can keep nothing forever while reporting success. For an ACTION, skipping
    # silently is usually right; for an ARTEFACT, the skip IS the failure, so silence is the bug.
    echo "warning: expected $what at $src but it does not exist -- nothing preserved" >&2
  fi
}

preserve_failure_evidence() {
  local label="$1" result="$2" log="$3"

  if [[ -z "$failure_artifact_dir" ]]; then
    echo "warning: no external volume for failure artefacts, so $label's .xcresult was not kept." >&2
    echo "         Set SPEEDREAD_FAILURE_ARTIFACT_DIR to keep it somewhere off the boot drive." >&2
    return 0
  fi

  local stamp dest
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$failure_artifact_dir/$stamp-$(echo "$label" | tr ' /' '--')"

  # Preserving evidence must never be the thing that fails the run -- the lane already failed
  # and that verdict is what matters.
  if ! mkdir -p "$dest" 2>/dev/null; then
    echo "warning: could not create $dest; $label's .xcresult was not kept." >&2
    return 0
  fi
  keep_artifact "$result" "$dest" "$label result bundle"
  keep_artifact "$log" "$dest" "$label log"
  echo "kept $label failure evidence: $dest" >&2
}

run_lane() {
  local label="$1"
  local scheme="$2"
  local plan="$3"
  local destination="$4"
  local result="$5"
  local log="$6"

  echo "Running $label..."
  if ! xcodebuild test \
    "${common_build_arguments[@]}" \
    -scheme "$scheme" \
    -testPlan "$plan" \
    -destination "$destination" \
    -resultBundlePath "$result" \
    >"$log" 2>&1; then
    echo "error: $label failed; final build output follows" >&2
    tail -n 120 "$log" | sed -f "$script_dir/lib/public-log.sed" >&2
    preserve_failure_evidence "$label" "$result" "$log"
    return 1
  fi

  # xcodebuild exits 0 for a plan that executed nothing, and a zero-test run reads as green
  # all the way to the coverage figure. Without this the gate can still fail -- but it fails
  # saying "coverage is below 82%", which is the wrong diagnosis and sends the next person
  # hunting a regression that does not exist. Name the real failure instead.
  local executed
  executed="$(awk -f "$script_dir/lib/executed-tests.awk" "$log")"
  if [[ "$executed" -eq 0 ]]; then
    echo "error: $label exited 0 but executed 0 tests -- the plan ran nothing" >&2
    preserve_failure_evidence "$label" "$result" "$log"
    return 1
  fi
  echo "  $label: $executed tests executed"

  # Which OS that was, read from the result bundle. Only the iOS lane takes the requirement: the
  # Studio has no watchOS 27 runtime, so its watch lane runs on watchOS 26.5.
  local required_major=""
  if [[ "$scheme" == "SpeedRead" ]]; then
    required_major="${SPEEDREAD_REQUIRE_IOS_MAJOR:-}"
  fi
  if ! python3 "$script_dir/lane-runtime.py" "$result" --require-ios-major "$required_major"; then
    preserve_failure_evidence "$label" "$result" "$log"
    return 1
  fi

  grep -E 'Test run with [0-9]+ tests|Executed [0-9]+ tests|\*\* TEST SUCCEEDED \*\*' "$log" \
    | tail -n 4 \
    || true
}

activate_sim "$ios_udid"
run_lane \
  "iOS hermetic unit lane" \
  "SpeedRead" \
  "Hermetic" \
  "$ios_destination" \
  "$ios_result" \
  "$ios_log"

activate_sim "$watch_udid"
run_lane \
  "watchOS hermetic unit lane" \
  "SpeedReadWatch Watch App" \
  "WatchHermetic" \
  "$watch_destination" \
  "$watch_result" \
  "$watch_log"

# Give the simulator back before the coverage analysis, which is pure xccov/python work on
# already-written .xcresult bundles and needs no booted device. That analysis is the slowest
# part of the run, so holding a simulator through it is the single longest idle hold here.
activate_sim ""

ios_json="$work_dir/ios-coverage.json"
watch_json="$work_dir/watch-coverage.json"
xcrun xccov view --report --json "$ios_result" >"$ios_json"
xcrun xccov view --report --json "$watch_result" >"$watch_json"

# Coverage exclusions use one "target name|path suffix|one-line reason" entry per
# line. This manifest is intentionally empty: every executable source line
# remains in the denominator.
coverage_exclusions=''

exclusions_json='[]'
while IFS= read -r exclusion; do
  [[ -z "$exclusion" ]] && continue
  IFS='|' read -r excluded_target excluded_suffix excluded_reason extra <<<"$exclusion"
  if [[ -z "$excluded_target" || -z "$excluded_suffix" || -z "$excluded_reason" || -n "${extra:-}" ]]; then
    echo "error: invalid coverage exclusion '$exclusion'" >&2
    exit 65
  fi
  exclusions_json="$(/usr/bin/jq -c \
    --arg target "$excluded_target" \
    --arg suffix "$excluded_suffix" \
    --arg reason "$excluded_reason" \
    '. + [{target: $target, suffix: $suffix, reason: $reason}]' \
    <<<"$exclusions_json")"
done <<<"$coverage_exclusions"

if [[ "$(/usr/bin/jq 'length' <<<"$exclusions_json")" -eq 0 ]]; then
  echo
  echo "Coverage exclusions: none"
else
  echo
  echo "Coverage exclusions:"
  /usr/bin/jq -r '.[] | "  \(.target): *\(.suffix) — \(.reason)"' <<<"$exclusions_json"
fi

target_totals() {
  local report_json="$1"
  local target_name="$2"

  /usr/bin/jq -r \
    --arg target "$target_name" \
    --argjson exclusions "$exclusions_json" '
      [
        .targets[]
        | select(.name == $target)
        | .files[]
        | . as $file
        | select(any($exclusions[];
            .target == $target and ($file.path | endswith(.suffix))) | not)
        | {covered: .coveredLines, executable: .executableLines}
      ]
      | if length == 0 then empty
        else [(map(.covered) | add), (map(.executable) | add)] | @tsv
        end
    ' "$report_json"
}

render_target() {
  local report_json="$1"
  local target_name="$2"
  local totals
  local covered
  local executable
  local percentage

  totals="$(target_totals "$report_json" "$target_name")"
  if [[ -z "$totals" ]]; then
    echo "error: xccov report did not contain target '$target_name'" >&2
    exit 66
  fi
  IFS=$'\t' read -r covered executable <<<"$totals"
  percentage="$(awk -v covered="$covered" -v executable="$executable" \
    'BEGIN { if (executable == 0) print "0.00"; else printf "%.2f", covered * 100 / executable }')"

  echo
  echo "$target_name overall: ${percentage}% (${covered}/${executable})"
  printf '%-10s %17s  %s\n' "Coverage" "Covered/Executable" "File"

  /usr/bin/jq -r \
    --arg target "$target_name" \
    --arg root "$repo_root" \
    --argjson exclusions "$exclusions_json" '
      .targets[]
      | select(.name == $target)
      | .files[]
      | . as $file
      | select(any($exclusions[];
          .target == $target and ($file.path | endswith(.suffix))) | not)
      | [
          (if .executableLines == 0 then 0 else (.coveredLines * 100 / .executableLines) end),
          .coveredLines,
          .executableLines,
          (if (.path | startswith($root + "/"))
           then .path[($root | length) + 1:]
           else .path
           end)
        ]
      | @tsv
    ' "$report_json" \
    | sort -t $'\t' -k1,1n -k4,4 \
    | while IFS=$'\t' read -r file_percentage file_covered file_executable file_path; do
        printf '%9.2f%% %8s/%-8s  %s\n' \
          "$file_percentage" "$file_covered" "$file_executable" "$file_path"
      done
}

ios_target="SpeedRead.app"
watch_target="SpeedReadWatch Watch App.app"
render_target "$ios_json" "$ios_target"
render_target "$watch_json" "$watch_target"

ios_attributable_json="$work_dir/ios-attributable.json"
watch_attributable_json="$work_dir/watch-attributable.json"

python3 "$script_dir/attributable-coverage.py" "$ios_json" "$repo_root"
python3 "$script_dir/attributable-coverage.py" --format json "$ios_json" "$repo_root" \
  >"$ios_attributable_json"
python3 "$script_dir/attributable-coverage.py" "$watch_json" "$repo_root"
python3 "$script_dir/attributable-coverage.py" --format json "$watch_json" "$repo_root" \
  >"$watch_attributable_json"

attributable_totals() {
  local metrics_json="$1"
  local target_name="$2"

  /usr/bin/jq -r \
    --arg target "$target_name" '
      .targets[]
      | select(.name == $target)
      | [.attributable.covered, .attributable.executable] | @tsv
    ' "$metrics_json"
}

ios_attributable_totals="$(attributable_totals "$ios_attributable_json" "$ios_target")"
watch_attributable_totals="$(attributable_totals "$watch_attributable_json" "$watch_target")"
if [[ -z "$ios_attributable_totals" || -z "$watch_attributable_totals" ]]; then
  echo "error: attributable coverage report omitted a shipping target" >&2
  exit 66
fi
IFS=$'\t' read -r ios_attributable_covered ios_attributable_executable <<<"$ios_attributable_totals"
IFS=$'\t' read -r watch_attributable_covered watch_attributable_executable <<<"$watch_attributable_totals"

# A lane failure preserves its log and result bundle. A GATE failure preserved nothing -- and
# the gate failing is the case you most need to diagnose, because the lanes were green and the
# question is which files moved. The JSONs are kilobytes; the rebuild they save is ~15 minutes.
# This is the same shape as the `if [ -e ]` with no else: the preservation step existed, and it
# was guarding the wrong event.
preserve_gate_evidence() {
  local why="$1"
  [[ -n "$failure_artifact_dir" ]] || return 0
  local dest="$failure_artifact_dir/$(date +%Y%m%d-%H%M%S)-coverage-gate"
  mkdir -p "$dest" || { echo "warning: could not create $dest" >&2; return 0; }
  printf '%s\n' "$why" >"$dest/why.txt"
  local kept=0
  for f in "$ios_json" "$watch_json" "$ios_attributable_json" "$watch_attributable_json"; do
    if [[ -f "$f" ]]; then
      cp "$f" "$dest/" && kept=$((kept + 1))
    else
      echo "warning: expected coverage json at $f but it does not exist" >&2
    fi
  done
  echo "kept coverage-gate evidence ($kept files): $dest" >&2
}

assert_attributable_lane_ran() {
  local target_name="$1"
  local covered="$2"
  local executable="$3"

  if (( executable > 0 && covered == 0 )); then
    echo "FAIL: $target_name has $executable attributable lines but 0 covered lines; "\
"the test lane is not exercising its named production files" >&2
    exit 1
  fi
}

assert_attributable_lane_ran "$ios_target" "$ios_attributable_covered" "$ios_attributable_executable"
assert_attributable_lane_ran "$watch_target" "$watch_attributable_covered" "$watch_attributable_executable"

ios_totals="$(target_totals "$ios_json" "$ios_target")"
watch_totals="$(target_totals "$watch_json" "$watch_target")"
IFS=$'\t' read -r ios_covered ios_executable <<<"$ios_totals"
IFS=$'\t' read -r watch_covered watch_executable <<<"$watch_totals"
combined_covered=$((ios_covered + watch_covered))
combined_executable=$((ios_executable + watch_executable))
combined_percentage="$(awk -v covered="$combined_covered" -v executable="$combined_executable" \
  'BEGIN { if (executable == 0) print "0.00"; else printf "%.2f", covered * 100 / executable }')"

combined_attributable_covered=$((ios_attributable_covered + watch_attributable_covered))
combined_attributable_executable=$((ios_attributable_executable + watch_attributable_executable))
combined_attributable_percentage="$(awk \
  -v covered="$combined_attributable_covered" \
  -v executable="$combined_attributable_executable" \
  'BEGIN { if (executable == 0) print "0.00"; else printf "%.2f", covered * 100 / executable }')"

combined_reach_percentage="$(awk \
  -v attributable="$combined_attributable_executable" \
  -v headline="$combined_executable" \
  'BEGIN { if (headline == 0) print "0.00"; else printf "%.2f", attributable * 100 / headline }')"

echo
echo "Combined HEADLINE:     ${combined_percentage}% (${combined_covered}/${combined_executable})"
echo "Combined ATTRIBUTABLE: ${combined_attributable_percentage}% "\
"(${combined_attributable_covered}/${combined_attributable_executable})"
echo "Combined REACH:        ${combined_reach_percentage}% "\
"(${combined_attributable_executable}/${combined_executable} executable lines)"
echo "Required ATTRIBUTABLE threshold: ${threshold}%"

if (( combined_attributable_executable == 0 )); then
  echo "FAIL: combined attributable coverage has no executable lines" >&2
  preserve_gate_evidence "combined attributable coverage has no executable lines"
  exit 1
fi

if awk \
  -v covered="$combined_attributable_covered" \
  -v executable="$combined_attributable_executable" \
  -v required="$threshold" \
  'BEGIN { exit !(covered * 100 / executable < required + 0) }'; then
  echo "FAIL: combined attributable coverage is below ${threshold}%" >&2
  preserve_gate_evidence "combined attributable ${combined_attributable_percentage}% < required ${threshold}%"
  exit 1
fi

echo "PASS: combined attributable coverage meets ${threshold}%"
