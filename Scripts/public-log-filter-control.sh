#!/bin/bash
#
# Control for Scripts/lib/public-log.sed, the filter the lane scripts put between xcodebuild
# and a public CI log.
#
# The fixture is the destination error from a real Studio run (2026-11-18, watchOS UI lane),
# with the device names and hardware ids replaced, because this file is public too. The shape
# -- tabs, braces, both apostrophes, the placeholder entry -- is verbatim.
#
# Both directions are asserted: the raw fixture must contain the device names (so a fixture
# edit cannot make the check vacuous), the filtered output must not, and every simulator line
# must survive unchanged (so a filter that deletes everything cannot pass).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="$script_dir/lib/public-log.sed"

fixture="$(printf '%s\n' \
  'xcodebuild: error: Unable to find a device matching the provided destination specifier:' \
  $'\t\t{ platform:watchOS Simulator, id:00000000-0000-0000-0000-000000000001 }' \
  '' \
  $'\tThe requested device could not be found because no available devices matched the request.' \
  '' \
  $'\tAvailable destinations for the "SpeedReadWatch Watch App" scheme:' \
  $'\t\t{ platform:watchOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-watchsimulator:placeholder, name:Any watchOS Simulator Device }' \
  '' \
  $'\tIneligible destinations for the "SpeedReadWatch Watch App" scheme:' \
  $'\t\t{ platform:macOS, arch:arm64e, id:00000000-000000000000000A, name:My Mac, error:My Mac’s macOS platform doesn’t match SpeedReadWatch Watch App.app’s supported platforms. }' \
  $'\t\t{ platform:iOS, arch:arm64e, id:00000000-000000000000000B, name:Owner’s iPad, error:Owner’s iPad’s iOS platform doesn’t match SpeedReadWatch Watch App.app’s supported platforms. }' \
  $'\t\t{ platform:iOS, arch:arm64e, id:00000000-000000000000000C, name:Owner\'s iPhone, error:Owner\'s iPhone’s iOS platform doesn’t match SpeedReadWatch Watch App.app’s supported platforms. }')"

failures=0
check() {  # $1 = description, $2 = 0 if the condition holds
  if [[ "$2" -eq 0 ]]; then echo "  ok: $1"; else echo "  FAIL: $1" >&2; failures=$((failures + 1)); fi
}

filtered="$(printf '%s\n' "$fixture" | sed -f "$filter")"

grep -q "Owner's iPhone" <<<"$fixture"; check "raw fixture names the iPhone" $?
grep -q "Owner’s iPad" <<<"$fixture"; check "raw fixture names the iPad" $?
! grep -q -E "Owner|My Mac|0000000000000000[ABC]" <<<"$filtered"; check "filtered output names no physical device" $?
[[ "$(grep -c 'hidden from public CI logs' <<<"$filtered")" -eq 3 ]]; check "all three physical devices are replaced" $?
diff <(grep 'Simulator' <<<"$fixture") <(grep 'Simulator' <<<"$filtered") >/dev/null; check "simulator lines pass through unchanged" $?
grep -q 'Unable to find a device' <<<"$filtered"; check "the error itself is kept" $?

if (( failures != 0 )); then
  echo "FAIL: public-log filter control ($failures)" >&2
  exit 1
fi
echo "PASS: public-log filter hides physical devices and keeps simulators"
