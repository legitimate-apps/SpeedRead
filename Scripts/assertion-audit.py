#!/usr/bin/env python3
"""Fail if any test body contains no assertion, or ends by sleeping instead of asserting.

A test that cannot fail inflates the count and hides the gap it appears to cover. This is
cheap enough to run on every change, so it runs as a gate rather than an audit.

TWO shapes, because the first check has a blind spot the second closes. Counting assertions
catches a body with none. It does NOT catch a body that asserts a screen appeared, then
sleeps for an external screenshotter and returns -- every assertion in it is about SETUP,
and nothing is asserted about the behaviour the test is named for. SpeedRead's UI suite was
mostly that shape: `testSendFirstBookToWatch` asserted the button existed, tapped it, slept
six seconds and ended, so it passed whether or not anything was ever sent.

The mechanical signature is precise and worth stating exactly: **a sleep with no assertion
after it.** That is a capture holder, not a test.
"""
import re, sys, pathlib

ASSERT = re.compile(r'#expect|#require|Issue\.record|XCTAssert|XCTFail|XCTUnwrap|withKnownIssue')
SLEEP = re.compile(r'Thread\.sleep|usleep\(|sleep\(')

# Tests allowed to end on a sleep, each with the reason. An exemption is a decision; a
# silent skip would rebuild the blind spot this check exists to remove.
SLEEP_EXEMPT: dict[str, str] = {}
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
bad, holders, total = [], [], 0
for p in files:
    src = p.read_text(errors='replace')
    for name, body, start in bodies(src):
        pre = src[max(0, start - 250):start]
        if not (name.startswith('test') or '@Test' in pre.rsplit('\n\n', 1)[-1]):
            continue
        if name in ('setUpWithError', 'tearDownWithError', 'setUp', 'tearDown'):
            continue
        total += 1
        where = f"{p.relative_to(repo.resolve())}:{src[:start].count(chr(10)) + 1}  {name}()"
        if not ASSERT.search(body):
            bad.append(where)
            continue
        sleeps = list(SLEEP.finditer(body))
        if sleeps and name not in SLEEP_EXEMPT:
            after = body[sleeps[-1].end():]
            if not ASSERT.search(after):
                holders.append(where)

print(f"test files: {len(files)}   tests: {total}   "
      f"assertion-free: {len(bad)}   sleep-then-nothing: {len(holders)}")
for b in bad:
    print("   assertion-free   " + b)
for h in holders:
    print("   capture holder   " + h + "   (sleeps, then asserts nothing)")
sys.exit(1 if bad or holders else 0)
