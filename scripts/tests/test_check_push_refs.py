"""The pre-push guard refuses pushes whose remote ref is main or gh-pages, and nothing else."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "check-push-refs.sh"
SHA = "1" * 40
ZERO = "0" * 40


def push(*lines: str) -> subprocess.CompletedProcess[str]:
    stdin = "".join(f"{line}\n" for line in lines)
    return subprocess.run(["bash", str(SCRIPT)], input=stdin, capture_output=True, text=True, check=False)


class CheckPushRefsTests(unittest.TestCase):
    def test_refuses_protected_branches(self) -> None:
        for branch in ("main", "gh-pages"):
            with self.subTest(branch=branch):
                result = push(f"refs/heads/feature {SHA} refs/heads/{branch} {SHA}")
                self.assertEqual(result.returncode, 1)
                self.assertIn(f"push to {branch} is not allowed", result.stderr)

    def test_refuses_when_any_ref_is_protected(self) -> None:
        result = push(
            f"refs/heads/feature {SHA} refs/heads/feature {ZERO}",
            f"refs/heads/main {SHA} refs/heads/main {SHA}",
        )
        self.assertEqual(result.returncode, 1)

    def test_allows_other_refs(self) -> None:
        for line in (
            f"refs/heads/main {SHA} refs/heads/u/someone/feature {ZERO}",
            f"(delete) {ZERO} refs/heads/old-feature {SHA}",
            f"refs/tags/v1.0 {SHA} refs/tags/v1.0 {ZERO}",
            f"refs/heads/x {SHA} refs/heads/mainline {ZERO}",
        ):
            with self.subTest(line=line):
                result = push(line)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_empty_push(self) -> None:
        self.assertEqual(push().returncode, 0)


if __name__ == "__main__":
    unittest.main()
