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
parser.add_argument("report", nargs="?")
parser.add_argument("--self-test", dest="self_test", action="store_true",
                    help="run the strip_comments positive control and exit")
parser.add_argument("repo_root", nargs="?", default=pathlib.Path(__file__).resolve().parents[1])
arguments = parser.parse_args()

def strip_comments(source):
    """Remove Swift comments so a type MENTIONED IN PROSE is not counted as a test naming it.

    This is not cosmetic. A file counts as "named" if a test references its declared type,
    and the match ran against raw source, so a doc comment reading "shared by BookmarkListView
    and HighlightListView" marked BOTH of those views as tested. They have 0/298 and 0/373
    coverage, so 671 zero-covered lines entered the ATTRIBUTABLE denominator and dropped the
    combined figure from ~84.4% to 78.41%, failing the gate.

    The incentive that creates is the dangerous part: writing an accurate doc comment lowers
    measured coverage, and the quickest way to "fix" the build is to delete the comment. That
    is laundering, and the instrument should not invite it.

    Swift block comments NEST, and `//` occurs inside string literals (every https:// URL), so
    this walks the source rather than running a regex over it. Strings are preserved: a type
    name in a string literal is a real reference (accessibility identifiers, for instance).
    """
    out = []
    i = 0
    n = len(source)
    depth = 0
    while i < n:
        c = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if depth:
            if c == "/" and nxt == "*":
                depth += 1; i += 2; continue
            if c == "*" and nxt == "/":
                depth -= 1; i += 2; continue
            i += 1; continue
        if c == "/" and nxt == "*":
            depth = 1; i += 2; continue
        if c == "/" and nxt == "/":
            while i < n and source[i] != "\n":
                i += 1
            continue
        if c == '"':
            out.append(c); i += 1
            while i < n:
                if source[i] == "\\":
                    out.append(source[i:i + 2]); i += 2; continue
                out.append(source[i])
                if source[i] == '"':
                    i += 1; break
                if source[i] == "\n":
                    i += 1; break
                i += 1
            continue
        out.append(c); i += 1
    return "".join(out)


SELF_TEST_CASES = [
    # (label, source, must_survive, must_vanish)
    ("line comment", "// BookmarkListView\nlet a = 1\n", ["let a"], ["BookmarkListView"]),
    ("doc comment", "/// shared by BookmarkListView\nstruct T {}\n", ["struct T"], ["BookmarkListView"]),
    ("block comment", "/* BookmarkListView */ let b = 2\n", ["let b"], ["BookmarkListView"]),
    # Swift block comments NEST; a non-nesting stripper stops at the first */ and leaks the rest.
    ("nested block", "/* outer /* inner BookmarkListView */ still HighlightListView */ let c = 3\n",
     ["let c"], ["BookmarkListView", "HighlightListView"]),
    # The // inside a URL must not eat the rest of the line -- this is the common false positive.
    ('url in string', 'let u = "https://x/BookmarkListView"\nlet d = 4\n', ["let d", "https://x"], []),
    # A type named in a STRING is a real reference (accessibility identifiers), so it survives.
    ("string literal reference", 'let id = "BookmarkListView"\n', ["BookmarkListView"], []),
    ("code reference", "BookmarkListView()\n", ["BookmarkListView"], []),
    ("escaped quote then slashes", 'let e = "a \\" // still string"\nlet f = 5\n', ["let f"], []),
    ("comment after code on one line", "let g = 6 // BookmarkListView\n", ["let g"], ["BookmarkListView"]),
]


def run_self_test():
    """Positive control for strip_comments.

    A stripper that fails OPEN (leaves prose in) silently re-creates the bug it exists to fix:
    a doc comment marks an untested file as tested and the coverage figure moves. A stripper
    that fails CLOSED (eats code) deletes real references and files vanish from the metric.
    Both directions are asserted here, per case, against text that would differ if it were wrong.
    """
    failures = 0
    for label, source, must_survive, must_vanish in SELF_TEST_CASES:
        cleaned = strip_comments(source)
        for fragment in must_survive:
            if fragment not in cleaned:
                print(f"FAIL [{label}] expected to survive: {fragment!r} -- got {cleaned!r}")
                failures += 1
        for fragment in must_vanish:
            if fragment in cleaned:
                print(f"FAIL [{label}] expected to vanish: {fragment!r} -- got {cleaned!r}")
                failures += 1
    if failures:
        print(f"FAIL: {failures} strip_comments self-test assertions failed")
        return 1
    print(f"PASS: strip_comments self-test -- {len(SELF_TEST_CASES)} cases, both directions asserted")
    return 0


if arguments.self_test:
    raise SystemExit(run_self_test())

if arguments.report is None:
    raise SystemExit("error: a coverage report is required unless --self-test is given")

with open(arguments.report) as report_file:
    report = json.load(report_file)
repo = pathlib.Path(arguments.repo_root)

test_src = strip_comments("\n".join(
    p.read_text(errors="replace")
    for p in repo.rglob("*.swift")
    if "Tests" in str(p) and ".build" not in str(p)
))

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
