#!/bin/bash
#
# Positive control for Scripts/lib/executed-tests.awk.
#
# The parser it guards decides whether a green lane actually ran anything. A parser that
# fails OPEN -- returning a plausible small non-zero for a log containing no tests -- would
# certify an empty lane as healthy, and nothing downstream could tell.
#
# So this control asserts EXPECTED COUNTS, never merely "a number came out". The awk regex-
# literal bug that shipped here produced 1 for every input, including an empty file; a
# control that checked "is the output a number?" would have passed it.
#
# Cheap, hermetic, no simulator, no build. Runs in CI alongside the other honesty gates.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/lib/executed-tests.awk"

if [[ ! -f "$parser" ]]; then
  echo "error: parser not found at $parser" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failures=0
checks=0

check() {
  local name="$1" expected="$2" body="$3"
  local fixture="$work_dir/fixture.log"
  printf '%s' "$body" >"$fixture"

  local actual
  actual="$(awk -f "$parser" "$fixture")"
  checks=$((checks + 1))

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name -- expected $expected, got $actual" >&2
    failures=$((failures + 1))
  fi
}

# --- The fail-open cases. These are the ones that matter. ---------------------------------

check "an empty log reports zero tests" 0 ""

check "a build log with no test summary reports zero tests" 0 \
'Build settings from command line:
    ARCHS = arm64
    ONLY_ACTIVE_ARCH = 1
** BUILD SUCCEEDED **
'

# The exact shape of the bug that shipped: digits everywhere, no test summary anywhere.
check "a log full of unrelated numbers still reports zero tests" 0 \
'note: Using new build system
2026-09-03 23:41:02.123 xcodebuild[12345:678901] Writing diagnostics
Touch /Volumes/X8/DerivedData/Build/Products/Debug-iphonesimulator/App.app
1 2 3 42 351 999
'

check "a lane that ran zero tests is reported as zero, not as success" 0 \
'Test run with 0 tests passed after 0.001 seconds.
** TEST SUCCEEDED **
'

# --- The real formats, asserted to the exact count -----------------------------------------

check "XCTest summary line" 42 \
'Executed 42 tests, with 0 failures (0 unexpected) in 1.234 (1.235) seconds
'

check "Swift Testing summary line" 351 \
'✔ Test run with 351 tests passed after 12.345 seconds.
'

check "singular test is not missed by the plural pattern" 1 \
'Executed 1 test, with 0 failures (0 unexpected) in 0.101 (0.102) seconds
'

check "a failing run still reports how many tests executed" 17 \
'✘ Test run with 17 tests failed after 3.210 seconds.
'

# A single xcodebuild log carries per-suite lines AND a final total; the largest is the total.
check "the largest count wins across many summary lines" 351 \
'Executed 12 tests, with 0 failures (0 unexpected) in 0.5 (0.5) seconds
Executed 40 tests, with 0 failures (0 unexpected) in 1.5 (1.5) seconds
✔ Test run with 351 tests passed after 12.345 seconds.
'

# Both harnesses in one log, which is what the iOS lane actually produces.
check "mixed XCTest and Swift Testing output takes the true maximum" 362 \
'Executed 11 tests, with 0 failures (0 unexpected) in 0.4 (0.4) seconds
✔ Test run with 362 tests passed after 30.0 seconds.
'

# --- Report --------------------------------------------------------------------------------

if (( failures != 0 )); then
  echo "FAIL: $failures of $checks executed-test parser checks failed" >&2
  exit 1
fi

echo "PASS: executed-test parser control -- $checks checks, expected counts all matched"
