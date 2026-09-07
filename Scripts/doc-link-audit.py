#!/usr/bin/env python3
"""Every relative link in a Markdown doc must resolve to something that exists.

This gate exists because of a specific failure on 2026-09-07. The roadmap's leg-28 changelog
entry ended "See [results and command receipts](2026-09-07-leg28-results.md) and [all
uncovered-line dispositions](2026-09-07-leg28-coverage-ledger.md)." Neither file existed. One
had been moved to docs/testing/ under a different name; the other was never written at all.

That is the same failure the other seven gates cover, wearing prose instead of code: a claim
that cannot fail. "See the receipts" with no receipts behind it reads exactly like "see the
receipts" with receipts behind it, and the evidence trail this project runs on is only worth
what its weakest unchecked citation is worth. A test that cannot fail inflates coverage; a
citation that cannot fail inflates confidence.

Heading anchors are checked too, and for the same reason: a link to a section that no longer
exists silently lands the reader at the top of the file, which looks like a working link.
"""

from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

# [text](target) -- target ends at the first whitespace (optional "title") or the closing paren.
LINK = re.compile(r'\[(?:[^\]\\]|\\.)*\]\(\s*(<[^>]*>|[^)\s]+)')
# Fenced code blocks are prose about links, not links.
FENCE = re.compile(r'^\s*(```|~~~)')
ATX = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
# Inline code spans are prose ABOUT link syntax, not link syntax. This file's own CLAUDE.md
# entry quotes the broken link it exists because of, and tripped on itself before this.
CODE_SPAN = re.compile(r'(`+)(?:(?!\1).)*\1', re.DOTALL)
FENCED_BLOCK = re.compile(r'^[ \t]*(```+|~~~+)[^\n]*\n.*?^[ \t]*\1[^\n]*$',
                          re.DOTALL | re.MULTILINE)
# Only the pieces GitHub actually strips when deriving an anchor.
ANCHOR_STRIP = re.compile(r'[^\w\- ]', re.UNICODE)

SKIP_DIRS = {".git", "build", "DerivedData", "__pycache__", "node_modules", ".build"}
EXTERNAL = ("http://", "https://", "mailto:", "tel:", "ftp://", "//")


def slug(heading: str) -> str:
    """GitHub's heading -> anchor derivation, close enough for our own docs."""
    text = re.sub(r'`([^`]*)`', r'\1', heading)                 # code spans keep their text
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)        # links keep their text
    text = re.sub(r'[*_~]', '', text)                           # emphasis markers vanish
    text = unicodedata.normalize("NFKD", text)
    text = ANCHOR_STRIP.sub('', text)
    return text.strip().lower().replace(' ', '-')


def headings(path: Path) -> set[str]:
    found: set[str] = set()
    fenced = False
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return found
    for line in lines:
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = ATX.match(line)
        if m:
            found.add(slug(m.group(2)))
    return found


def _blank(match: re.Match[str]) -> str:
    """Replace a span with spaces, keeping every newline so line numbers still line up."""
    return "".join("\n" if c == "\n" else " " for c in match.group(0))


def links_in(path: Path) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []

    # Blank out code BEFORE splitting into lines: a fenced block or an inline code span may
    # wrap across lines, and a per-line stripper misses exactly those. CLAUDE.md's own entry
    # about this gate quotes a broken link across a line break, and tripped the gate on itself.
    text = path.read_text(encoding="utf-8", errors="replace")
    text = FENCED_BLOCK.sub(_blank, text)
    text = CODE_SPAN.sub(_blank, text)

    for n, line in enumerate(text.splitlines(), 1):
        for m in LINK.finditer(line):
            target = m.group(1)
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            out.append((n, target))
    return out


def audit(root: Path) -> list[str]:
    problems: list[str] = []
    anchors: dict[Path, set[str]] = {}

    docs = sorted(
        p for p in root.rglob("*.md")
        if not any(part in SKIP_DIRS for part in p.parts)
    )
    for doc in docs:
        for lineno, raw in links_in(doc):
            target = raw.strip()
            if not target or target.startswith(EXTERNAL):
                continue

            path_part, _, fragment = target.partition("#")
            where = f"{doc.relative_to(root)}:{lineno}"

            if not path_part:                       # same-file anchor
                dest = doc
            else:
                dest = (doc.parent / path_part).resolve()
                if not dest.exists():
                    problems.append(f"{where}: link target does not exist -> {path_part}")
                    continue

            if fragment and dest.suffix == ".md":
                if dest not in anchors:
                    anchors[dest] = headings(dest)
                if slug(fragment) not in anchors[dest]:
                    problems.append(
                        f"{where}: no such heading in {path_part or dest.name} -> #{fragment}")
    return problems


def self_test() -> int:
    """Both directions. A gate only proven to pass is not proven to be a gate."""
    import tempfile

    cases = 0
    failures = 0
    positive = 0
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "sub").mkdir()
        (root / "sub" / "real.md").write_text(
            "# Real Heading\n\nbody\n\n## Second Section: with punctuation!\n", encoding="utf-8")

        def check(label: str, body: str, want_hit: bool) -> None:
            nonlocal cases, failures, positive
            cases += 1
            positive += 1 if want_hit else 0
            (root / "a.md").write_text(body, encoding="utf-8")
            hits = audit(root)
            got_hit = any("a.md" in h for h in hits)
            if got_hit != want_hit:
                failures += 1
                print(f"  FAIL {label}: expected hit={want_hit}, got {hits}", file=sys.stderr)

        # NEGATIVE -- must NOT be flagged.
        check("existing file", "[x](sub/real.md)\n", False)
        check("existing anchor", "[x](sub/real.md#real-heading)\n", False)
        check("punctuated anchor", "[x](sub/real.md#second-section-with-punctuation)\n", False)
        check("same-file anchor", "# Top\n\n[x](#top)\n", False)
        check("external url", "[x](https://example.com/nope.md)\n", False)
        check("link inside a fence", "```\n[x](sub/missing.md)\n```\n", False)
        check("link quoted in a code span", "prose `[x](sub/missing.md)` prose\n", False)
        check("real link beside a code span",
              "`[a](sub/gone.md)` and [b](sub/real.md)\n", False)
        check("code span wrapping a line break",
              "prose `[x](sub/gone.md) and\n[y](sub/alsogone.md)` prose\n", False)
        check("fenced block wrapping lines",
              "~~~\n[x](sub/gone.md)\n[y](sub/alsogone.md)\n~~~\n", False)

        # POSITIVE -- must be flagged. These are the real bug, reproduced.
        check("missing file", "[x](sub/missing.md)\n", True)
        check("the leg-28 bug", "See [receipts](2026-09-07-leg28-results.md).\n", True)
        check("missing anchor", "[x](sub/real.md#no-such-heading)\n", True)
        check("moved file, old path", "[x](real.md)\n", True)
        check("code span must not hide a real link on the same line",
              "`literal` [x](sub/missing.md)\n", True)

    if failures:
        print(f"FAIL: doc-link self-test -- {failures} of {cases} cases wrong", file=sys.stderr)
        return 1
    print(f"PASS: doc-link self-test -- {cases} cases, "
          f"{positive} positive / {cases - positive} negative, both directions asserted")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()

    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = audit(root)
    if problems:
        print(f"FAIL: {len(problems)} Markdown link(s) name something that does not exist",
              file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    print("PASS: every relative Markdown link resolves, headings included")
    return 0


if __name__ == "__main__":
    sys.exit(main())
