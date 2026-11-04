#!/usr/bin/env python3
"""Names the simulator a lane's tests ran on, read from that lane's own result bundle.

A green log doesn't say which OS it's about. The lanes lease a device on whichever runtime
sim-lease picks and delete the result bundle on success, and a test that branches on `#available`
passes on either side of the branch. So a run meant to cover iOS 27 could land on an older runtime
and stay green, with nothing to notice: sim-lease skips any runtime whose build number looks like
a seed, and a new Xcode's runtime can be one.

Every lane prints this. The iOS lanes of the pre-release run also pass --require-ios-major and fail
unless their tests really ran on that version. Anything unreadable fails, because a receipt that
can't be read proves nothing.

Usage:
  lane-runtime.py <result.xcresult> [--require-ios-major N]
  lane-runtime.py --self-test
"""

import argparse
import copy
import json
import subprocess
import sys

# Sampled from real bundles, 2026-11-03: the Studio's iOS 27 lane and the MBP's iOS 26 lane.
SAMPLED_IOS_27 = {
    "devicesAndConfigurations": [{"device": {
        "architecture": "arm64",
        "deviceName": "cc-speedread-i17p-eb6f",
        "modelName": "iPhone 17 Pro",
        "osBuildNumber": "24A434",
        "osVersion": "27.0",
        "platform": "iOS Simulator",
    }}]
}
SAMPLED_IOS_26 = {
    "devicesAndConfigurations": [{"device": {
        "architecture": "x86_64",
        "deviceName": "lease-speedread-tests-1793736836",
        "modelName": "iPhone 17 Pro",
        "osBuildNumber": "23D8133",
        "osVersion": "26.3.1",
        "platform": "iOS Simulator",
    }}]
}


def read_summary(bundle):
    done = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", bundle],
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        return None
    try:
        return json.loads(done.stdout)
    except ValueError:
        return None


def verdict(summary, required_major):
    """Returns (lines to print, why the lane must fail or None)."""
    if summary is None:
        return [], "couldn't read the result bundle's summary"
    devices = [entry.get("device") or {} for entry in summary.get("devicesAndConfigurations") or []]
    devices = [d for d in devices if d.get("platform") and d.get("osVersion")]
    if not devices:
        return [], "the result bundle names no device, so nothing says what these tests ran on"
    lines = [
        f"  ran on {d.get('modelName', 'unknown device')}, "
        f"{d['platform']} {d['osVersion']} ({d.get('osBuildNumber', 'unknown build')})"
        for d in devices
    ]
    if required_major:
        for d in devices:
            on_ios = d["platform"].startswith("iOS")
            if not on_ios or d["osVersion"].split(".")[0] != required_major:
                return lines, f"this lane has to run on iOS {required_major}"
    return lines, None


def self_test():
    wrong_platform = copy.deepcopy(SAMPLED_IOS_27)
    wrong_platform["devicesAndConfigurations"][0]["device"]["platform"] = "watchOS Simulator"
    no_version = copy.deepcopy(SAMPLED_IOS_27)
    del no_version["devicesAndConfigurations"][0]["device"]["osVersion"]

    cases = [
        ("no requirement, iOS 27", SAMPLED_IOS_27, "", True),
        ("no requirement, iOS 26", SAMPLED_IOS_26, "", True),
        ("requires 27, ran on 27", SAMPLED_IOS_27, "27", True),
        ("requires 26, ran on 26.3.1", SAMPLED_IOS_26, "26", True),
        ("requires 27, ran on 26.3.1", SAMPLED_IOS_26, "27", False),
        ("requires 26, ran on 27", SAMPLED_IOS_27, "26", False),
        ("requires 2, ran on 27: a prefix isn't a match", SAMPLED_IOS_27, "2", False),
        ("requires iOS 27, ran on another platform's 27", wrong_platform, "27", False),
        ("unreadable bundle", None, "", False),
        ("no devices", {"devicesAndConfigurations": []}, "", False),
        ("devices key missing", {}, "", False),
        ("device with no version", no_version, "", False),
    ]
    failures = 0
    for name, summary, required, expect_pass in cases:
        _, problem = verdict(summary, required)
        if (problem is None) != expect_pass:
            print(f"FAIL: {name}: expected {'pass' if expect_pass else 'fail'}, got {problem!r}")
            failures += 1
    if verdict(SAMPLED_IOS_27, "")[0] != ["  ran on iPhone 17 Pro, iOS Simulator 27.0 (24A434)"]:
        print("FAIL: the printed line doesn't name the model, platform, version and build")
        failures += 1
    if read_summary("/nonexistent/lane-runtime-self-test.xcresult") is not None:
        print("FAIL: a bundle that doesn't exist read as a summary")
        failures += 1
    if failures:
        return 1
    passing = sum(1 for case in cases if case[3])
    print(
        f"PASS: lane-runtime self-test -- {len(cases) + 2} cases, "
        f"{passing} pass / {len(cases) - passing} fail, both directions"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bundle", nargs="?")
    parser.add_argument("--require-ios-major", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.bundle:
        parser.error("name a .xcresult bundle, or pass --self-test")
    lines, problem = verdict(read_summary(args.bundle), args.require_ios_major)
    for line in lines:
        print(line)
    if problem:
        print(f"error: {problem}: {args.bundle}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
