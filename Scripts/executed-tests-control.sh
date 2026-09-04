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
# EVERY fixture below is a verbatim line from a real captured log in this repo. The first
# version of this file invented the Swift Testing summary as "Test run with 351 tests passed",
# a format this project never emits -- the real one is "Test run with 144 tests in 20 suites
# passed". The parser missed it and returned 0 for a healthy lane, and this control reported
# PASS, because both the parser and its control were written from the same wrong memory.
# A control whose ground truth is invented tests only that the author was self-consistent.
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
'✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
** TEST SUCCEEDED **
'

# --- The real formats, asserted to the exact count -----------------------------------------

check "XCTest summary line" 42 \
'Executed 42 tests, with 0 failures (0 unexpected) in 1.234 (1.235) seconds
'

# VERBATIM from docs/testing/COVERAGE-BASELINE.md -- what the iOS hermetic lane really prints.
# This is the format the first version of this control invented and therefore did not test.
check "Swift Testing summary, the format this project actually emits" 144 \
'✔ Test run with 144 tests in 20 suites passed after 0.776 seconds.
'

# VERBATIM from the same file -- the watchOS hermetic lane. Note the SINGULAR "suite".
check "singular suite is not missed by the plural pattern" 4 \
'✔ Test run with 4 tests in 1 suite passed after 0.005 seconds.
'

# VERBATIM from docs/testing/READING-TDD-EVIDENCE.md -- a red run still reports its count.
check "a failing Swift Testing run still reports how many tests executed" 11 \
'✘ Test run with 11 tests in 1 suite failed after 0.027 seconds with 29 issues.
'

# VERBATIM from the archived iOS UI lane log on the X8 (20260901-162224).
check "XCTest singular test" 1 \
'Executed 1 test, with 0 failures (0 unexpected)
'

check "XCTest plural with failures" 4 \
'Executed 4 tests, with 2 failures (0 unexpected)
'

# A single xcodebuild log carries per-suite lines AND a final total; the largest is the total.
check "the largest count wins across many summary lines" 144 \
'Executed 12 tests, with 0 failures (0 unexpected) in 0.5 (0.5) seconds
Executed 40 tests, with 0 failures (0 unexpected) in 1.5 (1.5) seconds
✔ Test run with 144 tests in 20 suites passed after 0.776 seconds.
'

# Both harnesses in one log, which is what the iOS lane actually produces.
check "mixed XCTest and Swift Testing output takes the true maximum" 362 \
'Executed 11 tests, with 0 failures (0 unexpected) in 0.4 (0.4) seconds
✔ Test run with 362 tests in 21 suites passed after 30.0 seconds.
'

# --- Report --------------------------------------------------------------------------------

if (( failures != 0 )); then
  echo "FAIL: $failures of $checks executed-test parser checks failed" >&2
  exit 1
fi

echo "PASS: executed-test parser control -- $checks checks, expected counts all matched"
