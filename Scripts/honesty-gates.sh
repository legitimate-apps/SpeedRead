#!/bin/bash
#
# Every cheap gate, in one place. No simulator, no build, seconds to run.
#
# This script is the SINGLE LIST of what must be true before a build is worth starting. It
# exists because the list kept living in two places -- CLAUDE.md prose and ci.yml steps -- and
# a list in two places is a list that disagrees with itself.
#
# That claim was false until 2026-09-06. Scripts/network-isolation-audit.py -- a static
# check costing 200ms -- was invoked only from Scripts/coverage.sh, i.e. AFTER two
# simulator boots and both hermetic lanes. It gated correctly and reported nothing late,
# so nothing ever drew attention to it; the cost was purely that a violation surfaced
# ~15 minutes into an expensive lane instead of before the build started. A gate in the
# wrong list is not a broken gate -- it is a gate you stop being able to afford to run.
#
# RUN IT BEFORE EVERY PUSH, not only in CI. One of these gates cannot work from inside CI at
# all: if .github/workflows/ci.yml is unparseable, GitHub creates no run, so a CI step that
# lints the workflow never executes. That is not hypothetical -- it happened here on
# 2026-09-04, when ${{ runner.temp }} in a workflow-level env block (where the runner context
# does not exist) made the file invalid. CI did not fail; it silently stopped existing, and the
# push looked completely normal. A gate that only runs inside the thing it guards is not a gate.
#
# The newest gate checks prose, not code, and belongs here for the same reason as the rest.
# On 2026-09-07 the roadmap's leg-28 entry ended "See [results and command receipts](...)"
# pointing at two files that did not exist -- one moved, one never written. A citation that
# cannot fail reads exactly like one that can, and this project's entire claim to honesty is
# its evidence trail. An uncheckable test inflates coverage; an uncheckable citation inflates
# confidence, and costs nothing to catch.

set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
run_gate() {
  local name="$1"; shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    return 0
  fi
  echo "GATE FAILED: $name" >&2
  failures=$((failures + 1))
}

# Ordered cheapest-first, and workflow validity first of all: if the workflow is broken,
# nothing else you learn here will run in CI anyway.
if command -v actionlint >/dev/null 2>&1; then
  run_gate "Workflow files are valid (actionlint)" actionlint
else
  echo "warning: actionlint not installed -- workflow validity UNCHECKED." >&2
  echo "         brew install actionlint. This gate is the one CI cannot run for itself." >&2
  failures=$((failures + 1))
fi

run_gate "No assertion-free tests"                  python3 Scripts/assertion-audit.py .
run_gate "Every target in a plan, every plan in a lane" python3 Scripts/lane-audit.py
run_gate "Shared sources are one file, not two"     python3 Scripts/shared-source-audit.py
run_gate "Test networking cannot reach the wire"   python3 Scripts/network-isolation-audit.py
run_gate "Executed-test parser reports true counts" Scripts/executed-tests-control.sh
run_gate "Public logs hide physical devices"       Scripts/public-log-filter-control.sh
run_gate "Coverage classifier ignores prose, not code" python3 Scripts/attributable-coverage.py --self-test
run_gate "Lane-runtime receipt fails when unreadable" python3 Scripts/lane-runtime.py --self-test
run_gate "Doc links name things that exist"         python3 Scripts/doc-link-audit.py .
run_gate "Doc-link gate catches a real broken link" python3 Scripts/doc-link-audit.py --self-test

printf '\n'
if (( failures != 0 )); then
  echo "FAIL: $failures honesty gate(s) failed" >&2
  exit 1
fi
echo "PASS: all honesty gates"
