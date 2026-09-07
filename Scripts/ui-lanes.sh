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

for tool in xcodebuild awk mktemp; do
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

# Simulators come from sim-lease, so the reap path owns them. A `name=` destination makes
# xcodebuild boot whatever stock device matches, which is an OWNERLESS booted simulator: nothing
# releases it, and on 2026-09-06 that class left six `xpcproxy_sim` stubs stuck in exec, wedged
# every full-table `ps` on the machine for two hours, and cost the fleet a reboot. A leased device
# is reaped when its owner dies; a stock one is not. Explicit destinations still win, so CI and a
# manual run can both override.
lease_sim() {  # $1 = device name, $2 = purpose ; echoes a destination, records the lease
  local device="$1" purpose="$2" udid
  udid="$(sim-lease create --project speedread --device "$device" --purpose "$purpose" \
    --ttl-hours 2 2>/dev/null | tail -1)"
  if [[ ! "$udid" =~ ^[0-9A-F-]{36}$ ]]; then
    return 1
  fi
  leased_sims+=("$udid")
  # Boot it here rather than letting xcodebuild do it. MEASURED 2026-09-07: a freshly created
  # watchOS device that xcodebuild boots itself is not ready for the UI test runner's install --
  # the lane dies with FBSOpenApplicationErrorDomain Code=4 "Unknown application display
  # identifier", deterministically, twice in a row. Pre-booting and waiting for bootstatus makes
  # the same lane pass 4/4. The unit lanes never showed it, because a hosted unit bundle installs
  # differently from an .xctrunner.
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  printf '%s' "$udid"
}

leased_sims=()
if command -v sim-lease >/dev/null 2>&1; then
  if [[ -z "${SPEEDREAD_IOS_DESTINATION:-}" ]]; then
    if ios_udid="$(lease_sim "iPhone 17 Pro" "ui")"; then
      ios_destination="platform=iOS Simulator,id=$ios_udid"
    fi
  fi
  if [[ -z "${SPEEDREAD_WATCH_DESTINATION:-}" ]]; then
    if watch_udid="$(lease_sim "Apple Watch Series 11 (46mm)" "ui-watch")"; then
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
cleanup() {
  # An EXIT trap reports the status of ITS OWN last command unless told otherwise. On
  # 2026-09-07 the sim-lease release loop below returned 1 on an empty array and turned a
  # fully green lane -- 385 + 80 tests, 91.37% -- into `exit 1`. Capture and re-return.
  local exit_status=$?
  rm -rf "$work_dir"
  if [[ -n "$leased_derived_data" ]]; then
    dd-lease release "$leased_derived_data" >/dev/null
  fi
  for leased_sim in ${leased_sims[@]+"${leased_sims[@]}"}; do
    if [[ -n "$leased_sim" ]]; then
      sim-lease release "$leased_sim" >/dev/null 2>&1 || true
    fi
  done
  return "$exit_status"
}
trap cleanup EXIT

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

run_lane "iOS UI lane" "SpeedRead" "UI" "$ios_destination"
run_lane "watchOS UI lane" "SpeedReadWatch Watch App" "WatchUI" "$watch_destination"

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: $failures UI lane(s) did not pass" >&2
  exit 1
fi

echo "PASS: both UI lanes executed and succeeded"
