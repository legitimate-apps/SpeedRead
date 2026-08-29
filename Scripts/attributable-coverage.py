#!/usr/bin/env python3
"""Split coverage into HEADLINE, ATTRIBUTABLE, REACH, and GHOST.

A host-app test bundle launches the app, so every file the app renders on launch reports
coverage with zero assertions behind it. Those lines ran; nothing would fail if they broke.
ATTRIBUTABLE counts only files whose declared types are actually named somewhere in the tests.

Usage: attributable-coverage.py [--format text|json] <xccov-report.json> [repo-root]
"""
import argparse
import json
import pathlib
import re

parser = argparse.ArgumentParser()
parser.add_argument("--format", choices=("text", "json"), default="text")
parser.add_argument("report")
parser.add_argument("repo_root", nargs="?", default=pathlib.Path(__file__).resolve().parents[1])
arguments = parser.parse_args()

with open(arguments.report) as report_file:
    report = json.load(report_file)
repo = pathlib.Path(arguments.repo_root)

test_src = "\n".join(
    p.read_text(errors="replace")
    for p in repo.rglob("*.swift")
    if "Tests" in str(p) and ".build" not in str(p)
)

DECL = re.compile(r'^\s*(?:public |internal |private |fileprivate |final |nonisolated )*'
                  r'(?:struct|class|enum|actor|protocol|extension)\s+(\w+)', re.M)

def declared_types(path):
    # xccov already reports an absolute `path` per file. The earlier version of this
    # inferred the file by globbing its BASENAME, which was wrong twice over: six sources
    # are symlinked into the watch target (one file, two paths) and SpineColor.swift exists
    # twice as two genuinely different files. Both failed to "unknown" and silently
    # understated reach. Read the field instead of re-deriving it.
    f = pathlib.Path(path)
    if not f.is_file():
        return None
    return set(DECL.findall(f.read_text(errors="replace")))

results = []
for t in report["targets"]:
    if not t["name"].endswith(".app"):
        continue
    rows = []
    for f in t["files"]:
        types = declared_types(f["path"])
        if types is None:
            named = None
        else:
            named = any(re.search(rf'\b{re.escape(ty)}\b', test_src) for ty in types)
        rows.append((f["name"], f["coveredLines"], f["executableLines"], named))

    # POSITIVE CONTROL — a classifier that fails toward a confident number is the same
    # hazard as a test that passes vacuously, and neither announces itself. Assert every
    # row is accounted for and every file resolved; report unresolved rows explicitly
    # instead of letting them vanish into "not attributable".
    unresolved = [r for r in rows if r[3] is None]
    tot_c = sum(r[1] for r in rows); tot_e = sum(r[2] for r in rows)
    assert tot_e == sum(f["executableLines"] for f in t["files"]), "row loss in classifier"
    assert len(rows) == len(t["files"]), "file loss in classifier"
    att = [r for r in rows if r[3]]
    att_c = sum(r[1] for r in att); att_e = sum(r[2] for r in att)
    orphan = [r for r in rows if r[3] is False and r[1] > 0]
    ghost_c = sum(r[1] for r in orphan)

    results.append({
        "name": t["name"],
        "headline": {
            "covered": tot_c,
            "executable": tot_e,
            "percentage": 0 if tot_e == 0 else tot_c * 100 / tot_e,
        },
        "attributable": {
            "covered": att_c,
            "executable": att_e,
            "percentage": 0 if att_e == 0 else att_c * 100 / att_e,
        },
        "reach": {
            "executable": att_e,
            "totalExecutable": tot_e,
            "percentage": 0 if tot_e == 0 else att_e * 100 / tot_e,
            "namedFiles": len(att),
            "totalFiles": len(rows),
        },
        "ghost": {
            "covered": ghost_c,
            "files": [
                {"name": name, "covered": covered, "executable": executable}
                for name, covered, executable, _ in sorted(orphan, key=lambda r: (-r[1], r[0]))
            ],
        },
        "unresolved": [
            {"name": name, "covered": covered, "executable": executable}
            for name, covered, executable, _ in unresolved
        ],
    })

if arguments.format == "json":
    print(json.dumps({"targets": results}, separators=(",", ":")))
else:
    for target in results:
        if target["unresolved"]:
            unresolved = target["unresolved"]
            print(f"  ⚠ CLASSIFIER BLIND on {len(unresolved)} file(s) — counted as unreached, "
                  f"which UNDERSTATES reach:")
            for row in unresolved:
                print(f"      {row['covered']:4d}/{row['executable']:4d}  {row['name']}")

        headline = target["headline"]
        attributable = target["attributable"]
        reach = target["reach"]
        ghost = target["ghost"]
        print(f"\n### {target['name']}")
        print(f"  HEADLINE     {headline['percentage']:6.2f}%  "
              f"({headline['covered']}/{headline['executable']})")
        print(f"  ATTRIBUTABLE {attributable['percentage']:6.2f}%  "
              f"({attributable['covered']}/{attributable['executable']})")
        print(f"  REACH        {reach['percentage']:6.2f}%  "
              f"({reach['executable']}/{reach['totalExecutable']} executable lines; "
              f"{reach['namedFiles']} of {reach['totalFiles']} files named)")
        if ghost["files"]:
            print(f"  GHOST COVERAGE: {ghost['covered']} covered lines in "
                  f"{len(ghost['files'])} files no test names")
            for row in ghost["files"]:
                percentage = 0 if row["executable"] == 0 else row["covered"] * 100 / row["executable"]
                print(f"      {percentage:6.2f}%  {row['covered']:4d}/{row['executable']:4d}  "
                      f"{row['name']}")
        else:
            print("  GHOST COVERAGE: none")
