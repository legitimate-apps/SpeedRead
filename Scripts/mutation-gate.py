#!/usr/bin/env python3
"""Manager-side mutation gate for SpeedRead.

Coverage says a line ran. This says an assertion would have NOTICED if the line were wrong.

Each mutation is (file, exact-old-substring, new-substring, label). We apply one at a time,
rebuild, run the hermetic lane, and record KILLED (suite failed = good) or SURVIVED (suite
still green = the covering tests pin nothing).

Two traps this guards against, both measured on the fleet 2026-08-29:
  * A mutation that did not recompile reads as SURVIVED. We assert the test binary's mtime
    advanced and that the build log shows a compile of the mutated file.
  * A mutation set chosen by whoever wrote the tests is biased toward mutations those tests
    already catch. These are chosen by the manager, aimed at numeric constants that can
    cancel out and at default arguments that tests pass explicitly.
"""
import subprocess, sys, os, json, time, pathlib, shutil, argparse

try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass

# Derive the repo root from this file's own location. Never hardcode an absolute path
# under a home directory — it bakes the macOS username into the repo, and it breaks the
# moment the checkout moves.
REPO = pathlib.Path(__file__).resolve().parent.parent
DD   = os.environ.get("SPEEDREAD_DERIVED_DATA_PATH", "/Volumes/Crucial X8/DerivedData/speedread-tests")  # external volume, no username
SPM  = os.environ.get("SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH", "/Volumes/Crucial X8/dev-caches/spm-clones")
def _dest(lane):
    """Read destinations LAZILY. They were read at import once, which meant --restore —
    the one path that runs after a crash, needing no simulator at all — died with a
    KeyError before it could put a live mutation back. Found the hard way when a killed
    run left a mutation in ORPCalculator.swift and the recovery tool refused to start."""
    var = "SPEEDREAD_IOS_DESTINATION" if lane == "ios" else "SPEEDREAD_WATCH_DESTINATION"
    try:
        return os.environ[var]
    except KeyError:
        print(f"error: {var} must be set to run mutations (not needed for --restore)")
        sys.exit(64)

# A mutation in a watch-only source file cannot be killed by the iOS lane — that file is not
# even in the iOS target, so it would report SURVIVED for a reason that has nothing to do with
# the tests. Route each mutation to the lane that actually compiles it.
def lane_for(path):
    return "watch" if path.startswith("SpeedReadWatch") else "ios"

def run_suite(logpath, plan=None, lane="ios"):
    scheme = "SpeedRead" if lane == "ios" else "SpeedReadWatch Watch App"
    dest = _dest(lane)
    cmd = ["xcodebuild", "test",
           "-project", "SpeedRead.xcodeproj", "-scheme", scheme,
           "-destination", dest,
           "-derivedDataPath", DD, "-clonedSourcePackagesDirPath", SPM,
           "-parallel-testing-enabled", "NO",
           # A mutation gate FAILS ON PURPOSE every time it succeeds, and xcodebuild's default
           # is `-collect-test-diagnostics on-failure`, which runs `simctl diagnose --timeout=600`.
           # Measured 2026-08-31: mutation 1 finished its tests in 3.2 s and then sat in
           # diagnostic collection for over four minutes before being killed. Across 22 mutations
           # that is hours of sysdiagnose nobody will ever read.
           "-collect-test-diagnostics", "never"]
    if plan: cmd += ["-testPlan", plan]
    with open(logpath, "w") as f:
        r = subprocess.run(cmd, cwd=REPO, stdout=f, stderr=subprocess.STDOUT)
    return r.returncode

def _log(logpath):
    try:
        return open(logpath, errors="replace").read()
    except OSError:
        return ""

def compiled(logpath, filename):
    """Proof the mutation actually reached the compiler."""
    log = _log(logpath)
    return "SwiftCompile" in log and filename in log

def tests_ran(logpath):
    """Proof the SUITE ACTUALLY EXECUTED, which is a different fact from 'the build failed'.

    A non-zero exit is only evidence of a kill if tests ran and one of them failed. A mutation
    that does not COMPILE also exits non-zero — and would otherwise be scored KILLED, which is a
    false kill: the strongest possible verdict awarded to a run that never tested anything.
    Same family as the INVALID check, one level down. (Owed to the peer-project TDD session, which hit
    it as `xcodebuild` returning EXIT=65 and "** TEST FAILED **" for a run that started zero
    tests — indistinguishable from real failure unless you count.)
    """
    log = _log(logpath)
    return ("Test run with" in log) or ("Test Case '-[" in log) or ("Executed " in log)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mutations", help="JSON list of {file, old, new, label}")
    ap.add_argument("--plan", default=None)
    ap.add_argument("--out", default="mutation-report.md")
    ap.add_argument("--restore", action="store_true",
                    help="Put back any file left mutated by a killed run, then exit.")
    args = ap.parse_args()

    scratch0 = pathlib.Path(os.environ.get("SCRATCH", "/tmp"))
    if args.restore:
        b = scratch0 / "mutation-backups"
        if not b.exists() or not any(b.iterdir()):
            print("nothing to restore"); sys.exit(0)
        for f in sorted(b.iterdir()):
            # Backup name is "<index>--<url-encoded repo-relative path>". Decode it rather than
            # searching for it; an ambiguous search is what broke this path before.
            if "--" in f.name:
                rel = f.name.split("--", 1)[1].replace("%2F", "/")
                target = REPO / rel
            else:
                # Legacy "<index>-<basename>" backup from an older run. Fall back to a search, but
                # refuse rather than guess when it is ambiguous.
                base = f.name.split("-", 1)[1]
                hits = [x for x in REPO.rglob(base) if ".build" not in str(x)]
                if len(hits) != 1:
                    print(f"CANNOT RESTORE {f.name}: {len(hits)} candidates — restore it by hand "
                          f"(the backup IS the pristine copy; diff it against HEAD first)")
                    continue
                target = hits[0]
            if not target.is_file():
                print(f"CANNOT RESTORE {f.name}: {target} does not exist"); continue
            target.write_text(f.read_text()); f.unlink()
            print("restored", target)
        sys.exit(0)

    muts = json.load(open(args.mutations))
    scratch = pathlib.Path(os.environ.get("SCRATCH", "/tmp"))

    # The first real run of this gate was SIGKILLed at mutation 3 of 22 and every verdict
    # already earned went with it, because the report was only written at the end. An hour
    # of simulator time is too expensive to hold in memory. Each verdict is appended to a
    # JSONL ledger the moment it is known, and a re-run skips what the ledger already has.
    ledger = pathlib.Path(args.out).with_suffix(".jsonl")
    done = {}
    if ledger.exists():
        for line in ledger.open():
            line = line.strip()
            if line:
                r = json.loads(line)
                done[r["label"]] = r
        if done:
            print(f"resuming: {len(done)} verdicts already in {ledger}")
            print("  ⚠️  REPLAYED verdicts were measured by an EARLIER run — possibly a different")
            print("      agent's. Delete the ledger before using this run to verify someone's work.")
    replayed = set()
    results = []
    backups = scratch / "mutation-backups"

    # A SIGKILL mid-mutation bypasses `finally` and leaves a mutation sitting in production
    # code. So the pristine copy goes to DISK before the file is touched, and a leftover
    # backup is a hard stop rather than something to work around.
    if backups.exists() and any(backups.iterdir()):
        print("REFUSING TO START: stale backups in", backups)
        print("A previous run was killed mid-mutation. Restore with --restore before continuing.")
        for b in sorted(backups.iterdir()):
            print("   ", b.name)
        sys.exit(2)
    backups.mkdir(parents=True, exist_ok=True)

    if not subprocess.run(["git", "diff", "--quiet"], cwd=REPO).returncode == 0:
        print("WARNING: working tree is dirty — a survivor may be your own uncommitted edit, "
              "not a gap in the suite.")

    for i, m in enumerate(muts, 1):
        if m["label"] in done:
            d = done[m["label"]]
            results.append((d["label"], d["verdict"], d["note"]))
            replayed.add(d["label"])
            print(f"[{i}/{len(muts)}] {m['label']}: {d['verdict']} (REPLAYED from ledger, not re-measured)")
            continue
        target = REPO / m["file"]
        original = target.read_text()
        def record(label, verdict, note):
            results.append((label, verdict, note))
            with ledger.open("a") as lf:
                lf.write(json.dumps({"label": label, "verdict": verdict, "note": note}) + "\n")

        if m["old"] not in original:
            record(m["label"], "SKIPPED", "anchor string not found — mutation is stale")
            print(f"[{i}/{len(muts)}] {m['label']}: SKIPPED (anchor not found)")
            continue
        if original.count(m["old"]) != 1:
            record(m["label"], "SKIPPED", f"anchor not unique ({original.count(m['old'])} matches)")
            print(f"[{i}/{len(muts)}] {m['label']}: SKIPPED (anchor not unique)")
            continue

        # The backup filename encodes the repo-RELATIVE PATH, not the basename. Six sources are
        # symlinked into the watch target, so a basename is ambiguous — and --restore, the one path
        # that runs after a crash, failed with "2 candidates" on exactly that. Same root cause as
        # the coverage classifier globbing basenames instead of reading the authoritative path:
        # never re-derive a location you already had.
        backup = backups / f"{i}--{m['file'].replace('/', '%2F')}"
        backup.write_text(original)
        target.write_text(original.replace(m["old"], m["new"]))
        log = scratch / f"mut-{i}.log"
        try:
            lane = lane_for(m["file"])
            rc = run_suite(log, args.plan, lane)
            recompiled = compiled(log, pathlib.Path(m["file"]).name)
            ran = tests_ran(log)
            if not recompiled:
                verdict, note = "INVALID", "mutation did not reach the compiler — result means nothing"
            elif not ran:
                verdict, note = "INVALID", "no test ever executed — a build failure is not a kill"
            elif rc != 0:
                verdict, note = "KILLED", "suite failed, as it should"
            else:
                verdict, note = "SURVIVED", "suite still green — nothing pins this"
        finally:
            target.write_text(original)
            backup.unlink(missing_ok=True)
        record(m["label"], verdict, note)
        print(f"[{i}/{len(muts)}] [{lane_for(m['file'])}] {m['label']}: {verdict} — {note}")

    # Not every survivor is a test gap, and a gate that cannot pass is not a gate. Two kinds
    # of mutation legitimately survive:
    #   * an EQUIVALENT mutant, which no test can kill because it does not change behaviour;
    #   * a mutation deliberately included as a prediction, to prove the gate reproduces a gap
    #     I already knew about.
    # Both carry "expect": "SURVIVED" in mutations.json with a "why". The gate fails only on
    # an outcome nobody predicted — otherwise the deliberate survivors would make every run red
    # and the signal would be ignored within a week.
    expected = {m["label"]: m.get("expect", "KILLED") for m in muts}
    reasons  = {m["label"]: m.get("why", "") for m in muts}
    unexpected = [r for r in results if r[1] != expected.get(r[0], "KILLED")]
    survivors  = [r for r in results if r[1] == "SURVIVED"]
    invalid    = [r for r in results if r[1] in ("INVALID", "SKIPPED")]
    killed     = [r for r in results if r[1] == "KILLED"]
    with open(args.out, "w") as f:
        f.write("# Mutation gate report\n\n")
        f.write("Coverage says a line ran. This says an assertion would have NOTICED if it were wrong.\n\n")
        f.write(f"Run {time.strftime('%Y-%m-%d %H:%M')} · {len(results)} mutations · "
                f"{len(killed)} killed · {len(survivors)} survived "
                f"({len(survivors)-len([r for r in unexpected if r[1]=='SURVIVED'])} of them expected) · "
                f"{len(invalid)} not counted · **{len(unexpected)} unexpected**\n\n")
        if replayed:
            f.write(f"⚠️ **{len(replayed)} of these verdicts were REPLAYED from a previous run's ledger "
                    f"and were not re-measured here.** Rows are marked *replayed*. To verify another "
                    f"agent's work, delete the ledger and re-run so every verdict is measured fresh.\n\n")
        else:
            f.write("Every verdict in this table was measured by this run.\n\n")
        f.write("| mutation | verdict | expected | measured | note |\n|---|---|---|---|---|\n")
        for label, verdict, note in results:
            exp = expected.get(label, "KILLED")
            prov = "*replayed*" if label in replayed else "this run"
            mark = "" if verdict == exp else " ⚠️"
            why = f" — {reasons[label]}" if reasons.get(label) and verdict == "SURVIVED" else ""
            f.write(f"| {label} | **{verdict}**{mark} | {exp} | {prov} | {note}{why} |\n")
        if unexpected:
            f.write("\n## Unexpected outcomes\n\n")
            for label, verdict, note in unexpected:
                f.write(f"- **{label}** — got {verdict}, expected {expected.get(label,'KILLED')}. {note}\n")
    print(f"\n{len(killed)} killed · {len(survivors)} survived · {len(invalid)} invalid/skipped · "
          f"{len(unexpected)} UNEXPECTED → {args.out}")
    for label, verdict, note in unexpected:
        print(f"  ⚠️  {label}: {verdict} (expected {expected.get(label,'KILLED')})")
    sys.exit(1 if unexpected else 0)

if __name__ == "__main__":
    main()
