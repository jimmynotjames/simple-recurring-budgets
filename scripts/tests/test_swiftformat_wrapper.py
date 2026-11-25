"""scripts/swiftformat.sh names the root config and each nested one on a file's path, outermost first."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "swiftformat.sh"

# Logs each call's arguments, one call per line, tab-separated; exits with $STUB_EXIT.
STUB = """#!/usr/bin/env bash
(IFS=$'\\t'; printf '%s\\n' "$*") >> "$STUB_LOG"
exit "${STUB_EXIT:-0}"
"""


class SwiftFormatWrapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.repo = self.tmp / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        shutil.copy(SCRIPT, self.repo / "scripts" / "swiftformat.sh")
        for path in (
            ".swiftformat",
            "App/A.swift",
            "UITests/.swiftformat",
            "UITests/B.swift",
            "UITests/Deep/.swiftformat",
            "UITests/Deep/C.swift",
            "UITestsOther/D.swift",
            "ignored/E.swift",
        ):
            (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / path).write_text("")
        (self.repo / ".gitignore").write_text("ignored/\n")
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        # Untracked but not ignored: still formatted when no files are given.
        subprocess.run(
            ["git", "add", ".gitignore", ".swiftformat", "UITests/.swiftformat", "UITests/Deep/.swiftformat", "App/A.swift"],
            cwd=self.repo,
            check=True,
        )
        self.stub = self.tmp / "swiftformat"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.log = self.tmp / "calls.log"

    def run_wrapper(self, *args: str, stub_exit: int = 0) -> tuple[subprocess.CompletedProcess[str], list[list[str]]]:
        env = {**os.environ, "SWIFTFORMAT": str(self.stub), "STUB_LOG": str(self.log), "STUB_EXIT": str(stub_exit)}
        result = subprocess.run(
            ["bash", str(self.repo / "scripts" / "swiftformat.sh"), *args],
            cwd=self.tmp,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        calls = [line.split("\t") for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_each_file_gets_the_configs_on_its_path(self) -> None:
        result, calls = self.run_wrapper("UITests/Deep/C.swift", "App/A.swift", "UITests/B.swift", "UITestsOther/D.swift")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            calls,
            [
                ["--config", ".swiftformat", "App/A.swift", "UITestsOther/D.swift"],
                ["--config", ".swiftformat", "--config", "UITests/.swiftformat", "UITests/B.swift"],
                [
                    "--config",
                    ".swiftformat",
                    "--config",
                    "UITests/.swiftformat",
                    "--config",
                    "UITests/Deep/.swiftformat",
                    "UITests/Deep/C.swift",
                ],
            ],
        )

    def test_no_files_means_every_not_ignored_swift_file(self) -> None:
        result, calls = self.run_wrapper("--lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ["--lint"] * 3)
        formatted = sorted(arg for call in calls for arg in call if arg.endswith(".swift"))
        self.assertEqual(formatted, ["App/A.swift", "UITests/B.swift", "UITests/Deep/C.swift", "UITestsOther/D.swift"])

    def test_skips_groups_with_no_files(self) -> None:
        _, calls = self.run_wrapper("App/A.swift")
        self.assertEqual(calls, [["--config", ".swiftformat", "App/A.swift"]])

    def test_passes_on_a_failure(self) -> None:
        result, calls = self.run_wrapper("--lint", "App/A.swift", "UITests/B.swift", stub_exit=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
