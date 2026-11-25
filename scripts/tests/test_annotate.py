"""The CI annotator reports a checker's findings whatever top-level shape its --json takes."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

import annotate  # noqa: E402


class NormalizeTests(unittest.TestCase):
    def test_list_payload_keeps_every_finding(self) -> None:
        collision = {"locale": "de", "first": "a", "second": "b", "value": "x", "reason": "r"}
        self.assertEqual(annotate.normalize([collision]), [collision])

    def test_distinct_pairs_finding_reads_as_a_pair(self) -> None:
        collision = {"locale": "de", "first": "a", "second": "b", "value": "x", "reason": "r"}
        self.assertEqual(annotate._finding_line(collision), "[de] a = b: 'x'")

    def test_empty_list_payload_has_no_findings(self) -> None:
        self.assertEqual(annotate.normalize([]), [])

    def test_errors_payload_is_tagged_by_severity(self) -> None:
        findings = annotate.normalize({"errors": [{"file": "a.md", "line": 1, "message": "m"}]})
        self.assertEqual(findings, [{"file": "a.md", "line": 1, "message": "m", "severity": "error"}])


if __name__ == "__main__":
    unittest.main()
