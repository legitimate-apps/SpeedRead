#!/usr/bin/env python3
"""Split coverage into HEADLINE vs ATTRIBUTABLE.

A host-app test bundle launches the app, so every file the app renders on launch reports
coverage with zero assertions behind it. Those lines ran; nothing would fail if they broke.
ATTRIBUTABLE counts only files whose declared types are actually named somewhere in the tests.

Usage: attributable.py <xccov-report.json> [repo-root]
"""
import json, re, sys, pathlib

report = json.load(open(sys.argv[1]))
repo = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "/path/to/SpeedRead")

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
    if unresolved:
        print(f"  ⚠ CLASSIFIER BLIND on {len(unresolved)} file(s) — counted as unreached, "
              f"which UNDERSTATES reach:")
        for name, c, e, _ in unresolved:
            print(f"      {c:4d}/{e:4d}  {name}")
    att = [r for r in rows if r[3]]
    att_c = sum(r[1] for r in att); att_e = sum(r[2] for r in att)
    orphan = [r for r in rows if r[3] is False and r[1] > 0]

    print(f"\n### {t['name']}")
    print(f"  HEADLINE     {tot_c/tot_e*100:6.2f}%  ({tot_c}/{tot_e})")
    print(f"  ATTRIBUTABLE {att_c/att_e*100:6.2f}%  ({att_c}/{att_e})   "
          f"— {len(att)} of {len(rows)} files are named by a test")
    if orphan:
        ghost = sum(r[1] for r in orphan)
        print(f"  GHOST COVERAGE: {ghost} covered lines in {len(orphan)} files no test names")
        for name, c, e, _ in sorted(orphan, key=lambda r: -r[1]):
            print(f"      {c/e*100:6.2f}%  {c:4d}/{e:4d}  {name}")
