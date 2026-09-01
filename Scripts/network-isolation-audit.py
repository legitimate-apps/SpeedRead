#!/usr/bin/env python3
"""Keeps hermetic test networking inside the guarded harness paths.

iOS 26.5 observations:
  * global URLProtocol registration intercepts URLSession.shared;
  * it does NOT cover URLSession(configuration:).

watchOS 26.5 observations:
  * explicit configuration.protocolClasses interception works;
  * global registration silently does NOT intercept URLSession.shared.

Therefore custom session construction is centralized in one support file per hermetic target, and
the watch trees may not use URLSession.shared at all. Integration tests are intentionally outside
this audit: their separately-gated purpose is live OPDS I/O. UI tests are also outside the two
hermetic unit targets; they exercise the launched app rather than making test-process requests.
"""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(
    sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
).resolve()

SCANNED_ROOTS = (
    "SpeedRead",
    "SpeedReadTests",
    "SpeedReadWatch Watch App",
    "SpeedReadWatch Watch AppTests",
)

CUSTOM_SESSION_FACTORIES = {
    "SpeedReadTests/NetworkIsolationSupport.swift",
    "SpeedReadWatch Watch AppTests/WatchNetworkIsolationSupport.swift",
}

WATCH_ROOTS = (
    "SpeedReadWatch Watch App/",
    "SpeedReadWatch Watch AppTests/",
)


def without_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//.*", "", source)


def swift_sources() -> list[pathlib.Path]:
    paths: list[pathlib.Path] = []
    for root_name in SCANNED_ROOTS:
        root = ROOT / root_name
        if root.exists():
            paths.extend(root.rglob("*.swift"))
    return sorted(paths)


def main() -> int:
    problems: list[str] = []
    seen_factories: set[str] = set()

    for path in swift_sources():
        relative = path.relative_to(ROOT).as_posix()
        source = without_comments(path.read_text(errors="ignore"))

        if "URLSession(configuration:" in source:
            if relative not in CUSTOM_SESSION_FACTORIES:
                problems.append(
                    f"{relative}: constructs a custom URLSession outside the guarded harness; "
                    "global URLProtocol registration does not cover custom configurations"
                )
            else:
                seen_factories.add(relative)

        if relative.startswith(WATCH_ROOTS):
            if "URLSession.shared" in source:
                problems.append(
                    f"{relative}: uses URLSession.shared on watchOS, where global URLProtocol "
                    "registration was observed to no-op; use WatchNetworkIsolationScope"
                )
            if "URLProtocol.registerClass" in source:
                problems.append(
                    f"{relative}: globally registers URLProtocol on watchOS even though that path "
                    "was observed not to intercept; use explicit protocolClasses"
                )

    missing_factories = CUSTOM_SESSION_FACTORIES - seen_factories
    for relative in sorted(missing_factories):
        problems.append(
            f"{relative}: expected guarded custom-session factory is missing or no longer "
            "constructs the session; the audit would otherwise be blind"
        )

    if problems:
        print("network isolation audit FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(
        "network isolation audit passed: iOS shared/default sessions globally guarded; "
        "custom sessions centralized; watchOS shared sessions forbidden"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
