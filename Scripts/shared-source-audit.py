#!/usr/bin/env python3
"""Fail when a filename exists in both the app and watch trees as two REAL files.

Seven of the eight filenames present in both of SpeedRead's source trees are symlinks to a
single file, so they cannot drift. The eighth, `SpineColor.swift`, was a real copy -- and it
had silently diverged: iOS grew a themed-palette overload that the watch copy never got, so
the same book rendered a different colour on phone and watch under any non-classic shelf
theme, with no test in the watch lane able to notice.

The method is a peer session's (peer-project TDD, 2026-09-01) and the general form is theirs and
mine jointly: **the residue of any de-duplication pass is a list of files someone judged
unshareable, and that judgement answered "COULD these be shared?" -- never "have these two
copies DIVERGED in ways that matter?"** The filename collision is the entire signal.

Their repo shares by copy throughout (23 pairs, zero identical), so all they can do is diff
periodically. A diff is a control someone has to remember to re-run. A symlink is a property.
This script exists to keep the property true.
"""

import pathlib
import sys

# Filenames deliberately kept as separate implementations, each with the reason and what
# stops the two drifting. An entry here is a DECISION; if it is only "we never got round to
# sharing it", that is a bug and belongs in the backlog, not in this dict.
DIVERGENCE_ALLOWED: dict[str, str] = {}

TREES = ("SpeedRead", "SpeedReadWatch Watch App")


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
                        pathlib.Path(__file__).resolve().parent.parent).resolve()
    trees = [root / t for t in TREES]
    missing = [t for t in trees if not t.is_dir()]
    if missing:
        print(f"shared-source audit FAILED: missing source tree(s) {missing} -- the audit is "
              f"blind, which is worse than a failure it can explain")
        return 1

    indexes = [{p.name: p for p in t.rglob("*.swift")} for t in trees]
    shared = sorted(set(indexes[0]) & set(indexes[1]))

    problems, linked = [], []
    for name in shared:
        a, b = indexes[0][name], indexes[1][name]
        if a.resolve() == b.resolve():
            linked.append(name)
        elif name in DIVERGENCE_ALLOWED:
            linked.append(f"{name} (separate by decision)")
        else:
            identical = a.read_bytes() == b.read_bytes()
            state = "byte-identical today" if identical else "ALREADY DIVERGED"
            problems.append(
                f"{name} exists in both trees as two real files ({state}). Share one source "
                f"-- a copy that is identical today is a copy that drifts tomorrow, and "
                f"nothing here would notice.\n      {a}\n      {b}")

    for name in sorted(set(DIVERGENCE_ALLOWED) - set(shared)):
        problems.append(f"DIVERGENCE_ALLOWED names {name!r}, which is not present in both "
                        f"trees -- delete the stale exemption")

    if problems:
        print("shared-source audit FAILED")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"shared-source audit passed: {len(shared)} filenames in both trees, all single-source")
    for name in linked:
        print(f"  {name}")
    for name, reason in sorted(DIVERGENCE_ALLOWED.items()):
        print(f"  {name}: SEPARATE by decision -- {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
