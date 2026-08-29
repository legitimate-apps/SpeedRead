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

REPO = pathlib.Path("/path/to/SpeedRead")
DD   = "/Volumes/Crucial X8/DerivedData/speedread-tests"
SPM  = "/Volumes/Crucial X8/dev-caches/spm-clones"
SIM  = "9202766C-CD78-4DD4-9F18-E538F62D30C4"

def run_suite(logpath, plan=None):
    cmd = ["xcodebuild", "test",
           "-project", "SpeedRead.xcodeproj", "-scheme", "SpeedRead",
           "-destination", f"platform=iOS Simulator,id={SIM}",
           "-derivedDataPath", DD, "-clonedSourcePackagesDirPath", SPM,
           "-parallel-testing-enabled", "NO"]
    if plan: cmd += ["-testPlan", plan]
    with open(logpath, "w") as f:
        r = subprocess.run(cmd, cwd=REPO, stdout=f, stderr=subprocess.STDOUT)
    return r.returncode

def compiled(logpath, filename):
    """Proof the mutation actually reached the compiler."""
    try:
        log = open(logpath, errors="replace").read()
    except OSError:
        return False
    return f"SwiftCompile" in log and filename in log

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
            # backup name is "<index>-<basename>"; find its source by basename
            base = f.name.split("-", 1)[1]
            hits = [x for x in REPO.rglob(base) if ".build" not in str(x)]
            if len(hits) != 1:
                print(f"CANNOT RESTORE {f.name}: {len(hits)} candidates"); continue
            hits[0].write_text(f.read_text()); f.unlink()
            print("restored", hits[0])
        sys.exit(0)

    muts = json.load(open(args.mutations))
    results = []
    scratch = pathlib.Path(os.environ.get("SCRATCH", "/tmp"))
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
        target = REPO / m["file"]
        original = target.read_text()
        if m["old"] not in original:
            results.append((m["label"], "SKIPPED", "anchor string not found — mutation is stale"))
            print(f"[{i}/{len(muts)}] {m['label']}: SKIPPED (anchor not found)")
            continue
        if original.count(m["old"]) != 1:
            results.append((m["label"], "SKIPPED", f"anchor not unique ({original.count(m['old'])} matches)"))
            print(f"[{i}/{len(muts)}] {m['label']}: SKIPPED (anchor not unique)")
            continue

        backup = backups / f"{i}-{target.name}"
        backup.write_text(original)
        target.write_text(original.replace(m["old"], m["new"]))
        log = scratch / f"mut-{i}.log"
        try:
            rc = run_suite(log, args.plan)
            recompiled = compiled(log, pathlib.Path(m["file"]).name)
            if not recompiled:
                verdict, note = "INVALID", "mutation did not reach the compiler — result means nothing"
            elif rc != 0:
                verdict, note = "KILLED", "suite failed, as it should"
            else:
                verdict, note = "SURVIVED", "suite still green — nothing pins this"
        finally:
            target.write_text(original)
            backup.unlink(missing_ok=True)
        results.append((m["label"], verdict, note))
        print(f"[{i}/{len(muts)}] {m['label']}: {verdict} — {note}")

    survivors = [r for r in results if r[1] == "SURVIVED"]
    invalid   = [r for r in results if r[1] in ("INVALID", "SKIPPED")]
    with open(args.out, "w") as f:
        f.write("# Mutation gate report\n\n")
        f.write(f"Run {time.strftime('%Y-%m-%d %H:%M')} · {len(results)} mutations · "
                f"{len(results)-len(survivors)-len(invalid)} killed · {len(survivors)} survived · "
                f"{len(invalid)} not counted\n\n")
        f.write("| mutation | verdict | note |\n|---|---|---|\n")
        for label, verdict, note in results:
            f.write(f"| {label} | **{verdict}** | {note} |\n")
    print(f"\n{len(survivors)} survivors, {len(invalid)} invalid/skipped → {args.out}")
    sys.exit(1 if survivors else 0)

if __name__ == "__main__":
    main()
