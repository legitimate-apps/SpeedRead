# Single source of truth for "how many tests did this lane actually execute?"
#
# Used by BOTH Scripts/coverage.sh and Scripts/ui-lanes.sh. It lives in one file on purpose:
# two copies of a parser diverge, and this one is load-bearing for every "the lane is green"
# claim the project makes.
#
# A lane that executes ZERO tests exits 0 and reads as green. Distinguishing "nothing ran"
# from "coverage regressed" is the entire job here -- without it, a broken run and a real
# regression produce the same message.
#
# Pull the number out of the MATCHED TEXT rather than by field position: XCTest and Swift
# Testing put it in different columns, and a positional parse that silently reads the wrong
# token reports 0 and fails a lane that was actually fine.
#
# The patterns below are STRINGS, not /regex/ literals. awk evaluates a regex literal in an
# argument list as a match against $0 FIRST, so the function would receive 1 or 0 and parse
# the digit "1" out of every log -- a wrong NON-ZERO, which reads as a healthy lane. That bug
# shipped here once and was caught only because a control asserted an expected COUNT rather
# than merely "a number came out". Scripts/executed-tests-control.sh is that control, and it
# is standing now rather than something a human remembered to run.

function biggest(pattern,   where, len, n) {
  where = match($0, pattern)
  if (where == 0) return
  len = RLENGTH
  n = 0 + substr($0, where, len)
  if (n > total) total = n
}

{
  biggest("[0-9]+ tests?,")              # XCTest:        "Executed 42 tests, with 0 failures"
  biggest("[0-9]+ tests? (passed|failed)")  # Swift Testing: "Test run with 351 tests passed"
}

END { print total + 0 }
