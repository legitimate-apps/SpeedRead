#!/usr/bin/env python3
"""Fail if any test body contains no assertion.

A test that cannot fail inflates the count and hides the gap it appears to cover. This is
cheap enough to run on every change, so it runs as a gate rather than an audit.
"""
import re, sys, pathlib

ASSERT = re.compile(r'#expect|#require|Issue\.record|XCTAssert|XCTFail|XCTUnwrap|withKnownIssue')
repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

def bodies(src):
    for m in re.finditer(r'func\s+(\w+)\s*\(', src):
        i = src.find('{', m.end())
        if i < 0:
            continue
        depth, j = 0, i
        while j < len(src):
            if src[j] == '{': depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0: break
            j += 1
        yield m.group(1), src[i:j + 1], m.start()

# resolve() so a file symlinked into a second target is audited once, not twice
files = sorted({p.resolve() for p in repo.rglob('*.swift')
                if 'Tests' in str(p) and 'DerivedData' not in str(p) and '.build' not in str(p)})
bad, total = [], 0
for p in files:
    src = p.read_text(errors='replace')
    for name, body, start in bodies(src):
        pre = src[max(0, start - 250):start]
        if not (name.startswith('test') or '@Test' in pre.rsplit('\n\n', 1)[-1]):
            continue
        if name in ('setUpWithError', 'tearDownWithError', 'setUp', 'tearDown'):
            continue
        total += 1
        if not ASSERT.search(body):
            bad.append(f"{p.relative_to(repo.resolve())}:{src[:start].count(chr(10)) + 1}  {name}()")

print(f"test files: {len(files)}   tests: {total}   assertion-free: {len(bad)}")
for b in bad:
    print("   " + b)
sys.exit(1 if bad else 0)
