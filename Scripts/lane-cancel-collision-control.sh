#!/bin/bash
#
# Usage: Scripts/lane-cancel-collision-control.sh Scripts/coverage.sh <label>
#
# NOT part of Scripts/honesty-gates.sh: this boots real simulators and takes minutes, while the
# gates are the cheap list that must run before every push. Run this by hand whenever the lease
# bookkeeping in coverage.sh or ui-lanes.sh changes.
#
# Reproduces the CI cancel-in-progress collision that broke a release-candidate run.
#
# Sequence: run A leases, run B leases, A is SIGTERMed. A's cleanup must release ONLY A's
# simulators. Previously A's query matched B's leases (same project, same null session, same
# purposes, created within 300s) and deleted B's simulator mid-test.
#
# CLAUDE_CODE_SESSION_ID is unset for both runs on purpose. My machine sets it; CI does not.
# Every local control I ran passed because that variable was silently discriminating the runs.
set -uo pipefail
script="$1"; label="$2"

owned() { sim-lease list --json 2>/dev/null | python3 -c "
import json,sys
pid=int(sys.argv[1])
try: leases=json.load(sys.stdin)
except ValueError: sys.exit(0)
for l in leases:
    if l.get('project')=='speedread' and l.get('owner_pid')==pid: print(l['udid'])" "$1"; }

wait_for_lease() { for _ in $(seq 1 90); do [[ -n "$(owned "$1")" ]] && return 0; sleep 1; done; return 1; }

env -u CLAUDE_CODE_SESSION_ID "$script" 99 >/dev/null 2>&1 &
A=$!
wait_for_lease "$A" || { echo "INCONCLUSIVE [$label]: run A never leased"; kill -9 "$A" 2>/dev/null; exit 2; }
env -u CLAUDE_CODE_SESSION_ID "$script" 99 >/dev/null 2>&1 &
B=$!
wait_for_lease "$B" || { echo "INCONCLUSIVE [$label]: run B never leased"; kill -9 "$A" "$B" 2>/dev/null; exit 2; }

b_before="$(owned "$B" | sort)"
echo "[$label] A=$A holds $(owned "$A" | wc -l | tr -d ' '), B=$B holds $(echo "$b_before" | wc -l | tr -d ' ') -- SIGTERM to A only"
kill -TERM "$A" 2>/dev/null; wait "$A" 2>/dev/null

for _ in $(seq 1 20); do [[ -z "$(owned "$A")" ]] && break; sleep 1; done
b_after="$(owned "$B" | sort)"
kill -9 "$B" 2>/dev/null; wait "$B" 2>/dev/null
sim-lease release $(owned "$B") >/dev/null 2>&1 || true

echo "[$label] A's leases after: $(owned "$A" | wc -l | tr -d ' ') (want 0)"
if [[ "$b_before" == "$b_after" ]]; then
  echo "PASS [$label]: A's cancellation left B's simulators intact"; exit 0
else
  echo "FAIL [$label]: A's cleanup destroyed B's simulators"
  echo "  B had:  $(echo "$b_before" | tr '\n' ' ')"
  echo "  B left: $(echo "$b_after"  | tr '\n' ' ')"
  exit 1
fi
