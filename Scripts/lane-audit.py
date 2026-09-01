#!/usr/bin/env python3
"""Fails when a test can exist, be wired, and still never run.

Three facts get conflated by every report this project produces, in both directions:

  1. a test TARGET exists in the Xcode project
  2. that target is a member of some .xctestplan
  3. some automated lane actually INVOKES that plan

SpeedRead has now been bitten at both seams. `SpeedReadWatch Watch AppTests` was real,
written, and in no plan, so it read as 0.00% coverage for months and silently failed a
standing goal. Later `UI.xctestplan` and `WatchUI.xctestplan` were correctly wired to
their targets and invoked by nothing, so CrownDirectionUITests -- the only test covering
the operator's reported crown-direction bug at the composition layer -- had run once by
hand and could never have caught a regression.

Neither gap announced itself. A target in no plan and a plan in no lane both look exactly
like a healthy project from the outside: the file is there, the target list is there, and
every green build agrees with them.
"""

import json
import pathlib
import re
import sys

# This audit lives in Scripts/ and IS invoked by the workflow, so without excluding itself its
# own EXEMPT_PLANS dict would count as "a lane names this plan" -- the exemption mechanism would
# silently satisfy the very check it is meant to guard. Identified by a content marker rather
# than by filename: the first version excluded `__file__`'s NAME, which stopped working the
# moment a control ran a copy under a different name, and the control then passed when it should
# have failed. Never re-derive an identity you can state outright.
SELF_MARKER = "lane-audit-self-identifying-marker"

# Repo root defaults to this script's parent, and is overridable by argument for the same
# reason Scripts/assertion-audit.py takes one: so the audit can be pointed at a checkout it
# does not live inside.
ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
                    pathlib.Path(__file__).resolve().parent.parent).resolve()

# Targets deliberately excluded from the "must be in a plan" rule, each with the reason.
# An empty exemption list is the goal; anything here is a decision, not an oversight.
EXEMPT_TARGETS: dict[str, str] = {}

# Plans deliberately run by a human rather than by CI. An exemption is a DECISION and must
# say who runs it and why -- a silent skip here would recreate exactly the blindness this
# script exists to remove.
EXEMPT_PLANS: dict[str, str] = {
    "NetworkIsolationPositiveControl": (
        "positive control for the hermetic network guard: it makes a deliberately un-stubbed "
        "request and MUST fail, so it can never run in a lane whose job is to be green. Run by "
        "hand via Scripts/network-isolation-positive-control.sh when changing the guard."
    ),
    "Integration": (
        "live OPDS suite; needs SPEEDREAD_LIVE_OPDS plus real server credentials from the "
        "environment, so it cannot run unattended in CI. Run by hand per CLAUDE.md before "
        "any change to OPDSClient or the Atom parser."
    ),
}


def project_test_targets() -> set[str]:
    pbxproj = (ROOT / "SpeedRead.xcodeproj" / "project.pbxproj").read_text(errors="ignore")
    targets = set()
    # Test targets are the ones carrying a TEST_HOST, a TEST_TARGET_NAME, or the
    # unit/ui-test product type. Match the product-type declaration and walk back to the
    # name on the same native-target record.
    for block in re.finditer(
        r"/\* Begin PBXNativeTarget section \*/(.*?)/\* End PBXNativeTarget section \*/",
        pbxproj,
        re.S,
    ):
        for target in re.finditer(
            r"name = (\"[^\"]+\"|[\w-]+);.*?productType = \"([^\"]+)\";",
            block.group(1),
            re.S,
        ):
            name, product_type = target.group(1).strip('"'), target.group(2)
            if "test" in product_type:
                targets.add(name)
    return targets


def plans() -> dict[str, set[str]]:
    found = {}
    for path in sorted(ROOT.glob("*.xctestplan")) + sorted(ROOT.glob("*/*.xctestplan")):
        data = json.loads(path.read_text())
        found[path.stem] = {
            t["target"]["name"]
            for t in data.get("testTargets", [])
            if t.get("enabled", True)
        }
    return found


def lane_sources() -> str:
    """Text of the workflows, plus ONLY the scripts those workflows actually invoke.

    The earlier version read every file under Scripts/, which made "a plan name appears
    somewhere" count as "a lane runs this plan". That is too lenient in exactly the way this
    audit exists to prevent, and it was caught by a real case:
    `NetworkIsolationPositiveControl.xctestplan` is named by
    `Scripts/network-isolation-positive-control.sh`, which no workflow invokes -- so the plan
    passed the audit while remaining as dormant as the UI plans had been. A script nobody runs
    is not a lane.
    """
    workflows = [p for p in sorted(ROOT.glob(".github/workflows/*.yml"))]
    workflow_text = "\n".join(p.read_text(errors="ignore") for p in workflows)

    parts = [workflow_text]
    for script in sorted(ROOT.glob("Scripts/*")):
        if not script.is_file():
            continue
        try:
            text = script.read_text(errors="ignore")
        except OSError:
            continue
        if SELF_MARKER in text:
            continue
        # Invoked means the workflow names it -- by path or by bare filename.
        if f"Scripts/{script.name}" in workflow_text or script.name in workflow_text:
            parts.append(text)
    return "\n".join(parts)


def main() -> int:
    targets = project_test_targets()
    plan_map = plans()
    lanes = lane_sources()
    problems = []

    if not targets:
        problems.append("could not parse any test targets out of project.pbxproj -- the "
                        "audit is blind, which is worse than a failure it can explain")
    if not plan_map:
        problems.append("found no .xctestplan files -- same blindness")

    covered_targets = set().union(*plan_map.values()) if plan_map else set()
    for target in sorted(targets - covered_targets - set(EXEMPT_TARGETS)):
        problems.append(f"test target {target!r} is a member of NO test plan, so it runs "
                        f"in no lane and appears in no report")

    for plan in sorted(plan_map):
        # A plan is invoked when its name appears as a quoted token in a lane script or a
        # workflow -- which is how every `-testPlan "<name>"` and `run_lane ... "<name>"`
        # call in this repo spells it.
        if plan in EXEMPT_PLANS:
            continue
        if f'"{plan}"' not in lanes:
            problems.append(f"test plan {plan!r} is invoked by NO automated lane -- its "
                            f"tests can never fail a build")

    for plan, members in sorted(plan_map.items()):
        if not members:
            problems.append(f"test plan {plan!r} enables no test targets")

    # An exemption naming something that no longer exists is not harmless: the dict decays into
    # a list of excuses for things that are not there, and the next reader trusts it.
    for plan in sorted(set(EXEMPT_PLANS) - set(plan_map)):
        problems.append(f"EXEMPT_PLANS names {plan!r}, which is not a test plan in this repo -- "
                        f"delete the stale exemption")
    for target in sorted(set(EXEMPT_TARGETS) - targets):
        problems.append(f"EXEMPT_TARGETS names {target!r}, which is not a test target in this "
                        f"repo -- delete the stale exemption")

    if problems:
        print("lane audit FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"lane audit passed: {len(targets)} test targets, {len(plan_map)} plans, "
          f"every target in a plan and every plan in a lane")
    for plan, reason in sorted(EXEMPT_PLANS.items()):
        print(f"  {plan}: EXEMPT from the lane rule -- {reason}")
    for plan, members in sorted(plan_map.items()):
        print(f"  {plan}: {', '.join(sorted(members))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
