#!/usr/bin/env python3
"""Contract tests for Scripts/coverage.sh using hermetic xccov fixtures."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
COVERAGE_SCRIPT = REPO_ROOT / "Scripts" / "coverage.sh"


class CoverageGateTests(unittest.TestCase):
    def test_gates_on_attributable_instead_of_headline(self):
        result = self.run_coverage(
            threshold="80",
            ios_named=(5, 10),
            watch_named=(5, 10),
            ghost=(90, 90),
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("combined attributable coverage is below 80%", result.stderr.lower())

    def test_zero_covered_attributable_target_fails_loudly(self):
        result = self.run_coverage(
            threshold="0",
            ios_named=(9, 10),
            watch_named=(0, 10),
            ghost=(90, 90),
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SpeedReadWatch Watch App.app", result.stderr)
        self.assertIn("attributable", result.stderr.lower())
        self.assertIn("0 covered lines", result.stderr.lower())

    def test_reports_all_metrics_ghosts_and_empty_exclusion_manifest_per_target(self):
        result = self.run_coverage(
            threshold="80",
            ios_named=(9, 10),
            watch_named=(9, 10),
            ghost=(90, 90),
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Coverage exclusions: none", result.stdout)
        for target in ("SpeedRead.app", "SpeedReadWatch Watch App.app"):
            target_section = result.stdout.split(f"### {target}", 1)[1]
            self.assertIn("HEADLINE", target_section)
            self.assertIn("ATTRIBUTABLE", target_section)
            self.assertIn("REACH", target_section)
            self.assertIn("GHOST", target_section)
        self.assertIn("PASS: combined attributable coverage meets 80%", result.stdout)

    def run_coverage(
        self,
        *,
        threshold: str,
        ios_named: tuple[int, int],
        watch_named: tuple[int, int],
        ghost: tuple[int, int],
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="speedread-coverage-tests-") as temporary:
            root = Path(temporary)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            ios_report = root / "ios.json"
            watch_report = root / "watch.json"

            ios_report.write_text(json.dumps(self.report(
                "SpeedRead.app",
                REPO_ROOT / "SpeedRead" / "Models" / "Book.swift",
                REPO_ROOT / "SpeedRead" / "ContentView.swift",
                ios_named,
                ghost,
            )))
            watch_report.write_text(json.dumps(self.report(
                "SpeedReadWatch Watch App.app",
                REPO_ROOT / "SpeedReadWatch Watch App" / "Shared" / "CrownSeek.swift",
                REPO_ROOT / "SpeedReadWatch Watch App" / "Views" / "WatchLibraryView.swift",
                watch_named,
                ghost,
            )))

            self.write_executable(bin_dir / "xcodebuild", """
                #!/bin/sh
                echo '** TEST SUCCEEDED **'
            """)
            self.write_executable(bin_dir / "xcrun", """
                #!/usr/bin/env python3
                import os
                import sys
                key = "FAKE_WATCH_REPORT" if "Watch" in sys.argv[-1] else "FAKE_IOS_REPORT"
                with open(os.environ[key]) as report:
                    print(report.read())
            """)

            environment = os.environ.copy()
            environment.update({
                "PATH": f"{bin_dir}:{environment['PATH']}",
                "FAKE_IOS_REPORT": str(ios_report),
                "FAKE_WATCH_REPORT": str(watch_report),
                "SPEEDREAD_DERIVED_DATA_PATH": str(root / "DerivedData"),
                "SPEEDREAD_CLONED_SOURCE_PACKAGES_PATH": str(root / "spm"),
            })
            return subprocess.run(
                [str(COVERAGE_SCRIPT), threshold],
                cwd=REPO_ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

    @staticmethod
    def report(
        target: str,
        named_path: Path,
        ghost_path: Path,
        named: tuple[int, int],
        ghost: tuple[int, int],
    ) -> dict:
        return {
            "targets": [{
                "name": target,
                "files": [
                    {
                        "name": named_path.name,
                        "path": str(named_path),
                        "coveredLines": named[0],
                        "executableLines": named[1],
                    },
                    {
                        "name": ghost_path.name,
                        "path": str(ghost_path),
                        "coveredLines": ghost[0],
                        "executableLines": ghost[1],
                    },
                ],
            }],
        }

    @staticmethod
    def write_executable(path: Path, contents: str):
        path.write_text(textwrap.dedent(contents).lstrip())
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
