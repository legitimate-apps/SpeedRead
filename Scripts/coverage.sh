#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: Scripts/coverage.sh <minimum-combined-line-coverage-percent>" >&2
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

for tool in xcodebuild xcrun awk sort mktemp; do
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
)
if [[ -n "$derived_data_path" ]]; then
  common_build_arguments+=( -derivedDataPath "$derived_data_path" )
fi
if [[ -n "$package_cache_path" ]]; then
  common_build_arguments+=( -clonedSourcePackagesDirPath "$package_cache_path" )
fi

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
    return 1
  fi

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

ios_totals="$(target_totals "$ios_json" "$ios_target")"
watch_totals="$(target_totals "$watch_json" "$watch_target")"
IFS=$'\t' read -r ios_covered ios_executable <<<"$ios_totals"
IFS=$'\t' read -r watch_covered watch_executable <<<"$watch_totals"
combined_covered=$((ios_covered + watch_covered))
combined_executable=$((ios_executable + watch_executable))
combined_percentage="$(awk -v covered="$combined_covered" -v executable="$combined_executable" \
  'BEGIN { if (executable == 0) print "0.00"; else printf "%.2f", covered * 100 / executable }')"

echo
echo "Combined shipping code: ${combined_percentage}% (${combined_covered}/${combined_executable})"
echo "Required threshold: ${threshold}%"

if awk -v covered="$combined_covered" -v executable="$combined_executable" -v required="$threshold" \
  'BEGIN { exit !(covered * 100 / executable < required + 0) }'; then
  echo "FAIL: combined line coverage is below ${threshold}%" >&2
  exit 1
fi

echo "PASS: combined line coverage meets ${threshold}%"
