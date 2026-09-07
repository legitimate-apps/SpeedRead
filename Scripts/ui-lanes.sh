#!/bin/bash

# Runs the two UI test plans, which no other automated lane executes.
#
# WHY THIS IS A SEPARATE SCRIPT AND NOT PART OF coverage.sh
#
# A UI test drives the whole app through its host process, so every SwiftUI body it walks
# past is recorded as "covered" with nothing asserting on it — the GHOST shape the
# attributable gate exists to reject. Folding these lanes into the coverage run would
# inflate the number the project is gated on with exactly the laundering the mandate
# forbids. So this script reports PASS/FAIL only and never touches coverage.
#
# WHAT IT IS GUARDING AGAINST
#
# Plan existence and lane execution are different facts. `UI.xctestplan` and
# `WatchUI.xctestplan` were both correctly wired to their targets and read as present in
# every report, while nothing on the machine ever invoked them — so
# CrownDirectionUITests, the only test covering the operator's reported crown-direction
# bug at the composition layer, had run once by hand and could never catch a regression.

set -euo pipefail

for tool in xcodebuild awk mktemp python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' was not found" >&2
    exit 69
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project="$repo_root/SpeedRead.xcodeproj"

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
    if ios_udid="$(lease_sim "iPhone 17 Pro" "ui")"; then
      leased_sims+=("$ios_udid")   # parent shell, not the subshell above
      ios_destination="platform=iOS Simulator,id=$ios_udid"
    fi
  fi
  if [[ -z "${SPEEDREAD_WATCH_DESTINATION:-}" ]]; then
    if watch_udid="$(lease_sim "Apple Watch Series 11 (46mm)" "ui-watch")"; then
      leased_sims+=("$watch_udid")   # parent shell, not the subshell above
      watch_destination="platform=watchOS Simulator,id=$watch_udid"
    fi
  fi
fi

derived_data_path="${SPEEDREAD_DERIVED_DATA_PATH:-}"
leased_derived_data=""
if [[ -z "$derived_data_path" ]] && command -v dd-lease >/dev/null 2>&1; then
  derived_data_path="$(dd-lease path --project speedread --purpose ui)"
  leased_derived_data="$derived_data_path"
fi

package_cache_path="${SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH:-}"
if [[ -z "$package_cache_path" ]] && command -v dd-lease >/dev/null 2>&1; then
  package_cache_path="$(dd-lease spm-path)"
fi

# Where a FAILING lane's evidence is kept. Written the same way as Scripts/coverage.sh, and it
# is here because it was NOT here first: the lane logs lived in work_dir and the cleanup trap
# deleted them on failure exactly as on success, so a red lane destroyed the only record of why.
# That is the identical defect fixed in coverage.sh an hour earlier and not propagated to this
# file -- which is itself the lesson. Never the boot volume; no external drive means a warning
# and no artefact.
failure_artifact_dir="${SPEEDREAD_FAILURE_ARTIFACT_DIR:-}"
if [[ -z "$failure_artifact_dir" && -d "/Volumes/Crucial X8" ]]; then
  failure_artifact_dir="/Volumes/Crucial X8/agent-artifacts/speedread-lane-failures"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/speedread-ui.XXXXXX")"

common_build_arguments=(
  -project "$project"
  -parallel-testing-enabled NO
  # xcodebuild's default is `-collect-test-diagnostics on-failure`, which runs
  # `simctl diagnose --timeout=600` on every red run and presents as a silent hang.
  -collect-test-diagnostics never
)
if [[ -n "$derived_data_path" ]]; then
  common_build_arguments+=( -derivedDataPath "$derived_data_path" )
fi
if [[ -n "$package_cache_path" ]]; then
  common_build_arguments+=( -clonedSourcePackagesDirPath "$package_cache_path" )
fi

failures=0

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
  local label="$1" log="$2" result="$3"

  if [[ -z "$failure_artifact_dir" ]]; then
    echo "warning: no external volume for failure artefacts, so $label's log was not kept." >&2
    return 0
  fi

  local dest
  dest="$failure_artifact_dir/$(date +%Y%m%d-%H%M%S)-$(echo "$label" | tr ' /' '--')"
  # Preserving evidence must never be what fails the run; the lane already failed.
  if ! mkdir -p "$dest" 2>/dev/null; then
    echo "warning: could not create $dest; $label's log was not kept." >&2
    return 0
  fi
  keep_artifact "$log" "$dest" "$label log"
  keep_artifact "$result" "$dest" "$label result bundle"
  # Printing the destination is the only way a human ever notices this pointing at the wrong
  # path. A peer's preservation step silently kept nothing for weeks because it built a bad
  # filename behind an `if [ -e ]` guard -- a backup nobody has ever restored from.
  echo "kept $label failure evidence: $dest" >&2
}

run_lane() {
  local label="$1"
  local scheme="$2"
  local plan="$3"
  local destination="$4"
  local log="$work_dir/${plan}.log"
  local result="$work_dir/${plan}.xcresult"

  echo "Running $label..."
  if ! xcodebuild test \
    "${common_build_arguments[@]}" \
    -scheme "$scheme" \
    -testPlan "$plan" \
    -destination "$destination" \
    -resultBundlePath "$result" \
    >"$log" 2>&1; then
    echo "error: $label failed; final build output follows" >&2
    tail -n 120 "$log" >&2
    preserve_failure_evidence "$label" "$log" "$result"
    failures=$((failures + 1))
    return
  fi

  # A lane that executes ZERO tests exits 0 and reads as green. Prove tests actually ran
  # before calling the lane passed. The parser and the reasoning behind it live in
  # Scripts/lib/executed-tests.awk; Scripts/executed-tests-control.sh keeps it honest.
  local executed
  executed="$(awk -f "$script_dir/lib/executed-tests.awk" "$log")"

  if [[ "$executed" -eq 0 ]]; then
    echo "error: $label reported success but executed 0 tests — the plan ran nothing" >&2
    failures=$((failures + 1))
    return
  fi

  echo "  $label: $executed tests executed"
}

activate_sim "$ios_udid"
run_lane "iOS UI lane" "SpeedRead" "UI" "$ios_destination"

activate_sim "$watch_udid"
run_lane "watchOS UI lane" "SpeedReadWatch Watch App" "WatchUI" "$watch_destination"

# Give the last simulator back before the summary rather than at trap time: nothing after this
# point needs a booted device, and on this machine a booted simulator is the scarce resource.
activate_sim ""

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: $failures UI lane(s) did not pass" >&2
  exit 1
fi

echo "PASS: both UI lanes executed and succeeded"
