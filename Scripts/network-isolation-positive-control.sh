#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
destination="${SPEEDREAD_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"

derived_data_path="${SPEEDREAD_DERIVED_DATA_PATH:-}"
leased_derived_data=""
if [[ -z "$derived_data_path" ]] && command -v dd-lease >/dev/null 2>&1; then
  derived_data_path="$(dd-lease path --project speedread-network-control --purpose tests)"
  leased_derived_data="$derived_data_path"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/speedread-network-control.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
  if [[ -n "$leased_derived_data" ]]; then
    dd-lease release "$leased_derived_data" >/dev/null
  fi
}
trap cleanup EXIT

log="$work_dir/positive-control.log"
arguments=(
  -project "$repo_root/SpeedRead.xcodeproj"
  -scheme "SpeedRead"
  -testPlan "NetworkIsolationPositiveControl"
  -only-test-configuration "Positive Control"
  -destination "$destination"
  -parallel-testing-enabled NO
  -collect-test-diagnostics never
)
if [[ -n "$derived_data_path" ]]; then
  arguments+=( -derivedDataPath "$derived_data_path" )
fi
if command -v dd-lease >/dev/null 2>&1; then
  arguments+=( -clonedSourcePackagesDirPath "$(dd-lease spm-path)" )
fi

set +e
xcodebuild test \
  "${arguments[@]}" \
  >"$log" 2>&1
build_status=$?
set -e

if [[ "$build_status" -eq 0 ]]; then
  echo "network isolation positive control FAILED: the deliberately un-stubbed request stayed green" >&2
  tail -n 80 "$log" >&2
  exit 1
fi

if ! grep -Fq "Hermetic network isolation blocked an un-stubbed request" "$log" \
  || ! grep -Eq '\*\* TEST FAILED \*\*|Testing failed:' "$log"; then
  echo "network isolation positive control FAILED for the wrong reason" >&2
  tail -n 120 "$log" >&2
  exit 1
fi

grep -E 'Hermetic network isolation blocked|Test run with|Testing failed:|\*\* TEST FAILED \*\*' "$log" | tail -n 8
echo "PASS: deliberately un-stubbed request made the hermetic test plan fail"
