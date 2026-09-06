#!/usr/bin/env python3
"""Fail when a filename exists in both trees of a pair as two REAL files.

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

The TEST trees are audited on the same rule and for a sharper reason. A drifted source copy
renders the wrong colour; a drifted TEST copy takes an assertion out of one platform's lane
and leaves that lane reporting green. `RSVPRenderProbe.swift` is shared across both test trees
today only because the delegate who wrote it chose to symlink it -- nothing required it. This
gate is what turns that choice into a property.
"""

import pathlib
import sys

# Filenames deliberately kept as separate implementations, each with the reason and what
# stops the two drifting. An entry here is a DECISION; if it is only "we never got round to
# sharing it", that is a bug and belongs in the backlog, not in this dict.
#
# Keyed per pair, because an exemption argued for a shipping source file is not an argument
# about a test file that happens to share its name.
TREE_PAIRS: tuple[tuple[str, tuple[str, str], dict[str, str]], ...] = (
    ("source", ("SpeedRead", "SpeedReadWatch Watch App"), {}),
    ("test", ("SpeedReadTests", "SpeedReadWatch Watch AppTests"), {}),
)


def audit_pair(root: pathlib.Path, label: str, tree_names: tuple[str, str],
               divergence_allowed: dict[str, str]) -> tuple[list[str], list[str], int]:
    """Return (problems, linked, shared_count) for one pair of trees."""
    trees = [root / t for t in tree_names]
    missing = [str(t) for t in trees if not t.is_dir()]
    if missing:
        return ([f"missing {label} tree(s) {missing} -- the audit is blind, which is worse "
                 f"than a failure it can explain"], [], 0)

    indexes = [{p.name: p for p in t.rglob("*.swift")} for t in trees]
    shared = sorted(set(indexes[0]) & set(indexes[1]))

    problems, linked = [], []
    for name in shared:
        a, b = indexes[0][name], indexes[1][name]
        if a.resolve() == b.resolve():
            linked.append(name)
        elif name in divergence_allowed:
            linked.append(f"{name} (separate by decision)")
        else:
            identical = a.read_bytes() == b.read_bytes()
            state = "byte-identical today" if identical else "ALREADY DIVERGED"
            problems.append(
                f"[{label}] {name} exists in both trees as two real files ({state}). Share one "
                f"source -- a copy that is identical today is a copy that drifts tomorrow, and "
                f"nothing here would notice.\n      {a}\n      {b}")

    for name in sorted(set(divergence_allowed) - set(shared)):
        problems.append(f"[{label}] DIVERGENCE_ALLOWED names {name!r}, which is not present in "
                        f"both trees -- delete the stale exemption")

    return problems, linked, len(shared)


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
                        pathlib.Path(__file__).resolve().parent.parent).resolve()

    all_problems: list[str] = []
    summaries: list[str] = []
    for label, tree_names, divergence_allowed in TREE_PAIRS:
        problems, linked, shared_count = audit_pair(root, label, tree_names, divergence_allowed)
        all_problems.extend(problems)
        if not problems:
            summaries.append(f"  {label}: {shared_count} filenames in both trees, all single-source")
            summaries.extend(f"    {name}" for name in linked)
            summaries.extend(f"    {name}: SEPARATE by decision -- {reason}"
                             for name, reason in sorted(divergence_allowed.items()))

    if all_problems:
        print("shared-source audit FAILED")
        for p in all_problems:
            print(f"  - {p}")
        return 1

    print(f"shared-source audit passed across {len(TREE_PAIRS)} tree pairs")
    for line in summaries:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
