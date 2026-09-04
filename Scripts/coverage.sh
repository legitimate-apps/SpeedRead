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

derived_data_path="${SPEEDREAD_DERIVED_DATA_PATH:-}"
leased_derived_data=""
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
cleanup() {
  rm -rf "$work_dir"
  if [[ -n "$leased_derived_data" ]]; then
    dd-lease release "$leased_derived_data" >/dev/null
  fi
}
trap cleanup EXIT

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
    tail -n 120 "$log" >&2
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

  grep -E 'Test run with [0-9]+ tests|Executed [0-9]+ tests|\*\* TEST SUCCEEDED \*\*' "$log" \
    | tail -n 4 \
    || true
}

run_lane \
  "iOS hermetic unit lane" \
  "SpeedRead" \
  "Hermetic" \
  "$ios_destination" \
  "$ios_result" \
  "$ios_log"

run_lane \
  "watchOS hermetic unit lane" \
  "SpeedReadWatch Watch App" \
  "WatchHermetic" \
  "$watch_destination" \
  "$watch_result" \
  "$watch_log"

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
