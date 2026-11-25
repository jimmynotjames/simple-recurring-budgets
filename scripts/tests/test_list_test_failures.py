"""Each failure in a result bundle's test tree prints as one line naming its test and file:line."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from list_test_failures import (  # noqa: E402
    build_report,
    counts_from_tree,
    failures_from_tree,
)

ROOT = Path("/repo")


def _failure(text: str, file: str | None = None, line: int | None = None) -> dict:
    node: dict = {"nodeType": "Failure Message", "name": text}
    if file:
        node["sourceLocation"] = {"filePath": file, "lineNumber": line}
    return node


def _case(identifier: str, *children: dict, result: str = "Passed") -> dict:
    return {"nodeType": "Test Case", "nodeIdentifier": identifier, "name": identifier.split("/")[-1],
            "result": result, "children": list(children)}


def _tree(*cases: dict) -> dict:
    return {"testNodes": [{"nodeType": "Test Plan", "children": [
        {"nodeType": "UI test bundle", "children": [{"nodeType": "Test Suite", "children": list(cases)}]},
    ]}]}


class FailuresFromTreeTests(unittest.TestCase):
    def test_failure_names_its_test_case_and_repo_relative_line(self) -> None:
        tree = _tree(_case(
            "checklistCreateUITest/testCreateBlankChecklist()",
            _failure("XCTAssertTrue failed", "/repo/checklists/checklistsUITests/checklistCreateUITest.swift", 235),
        ))
        self.assertEqual(failures_from_tree(tree, ROOT), [{
            "test": "checklistCreateUITest/testCreateBlankChecklist()",
            "location": "checklists/checklistsUITests/checklistCreateUITest.swift:235",
            "text": "XCTAssertTrue failed",
        }])

    def test_passing_cases_print_nothing(self) -> None:
        self.assertEqual(failures_from_tree(_tree(_case("A/testPasses()")), ROOT), [])

    def test_failure_inside_a_repetition_keeps_its_test_case(self) -> None:
        repetition = {"nodeType": "Repetition", "name": "Repetition 2 of 3",
                      "children": [_failure("notice missing", "/repo/A.swift", 9)]}
        found = failures_from_tree(_tree(_case("A/testFlaky()", repetition)), ROOT)
        self.assertEqual([(f["test"], f["location"]) for f in found], [("A/testFlaky()", "A.swift:9")])

    def test_multiline_text_collapses_to_one_line(self) -> None:
        tree = _tree(_case("A/testB()", _failure("Failed to tap\n  Button", "/repo/A.swift", 3)))
        self.assertEqual(failures_from_tree(tree, ROOT)[0]["text"], "Failed to tap Button")

    def test_missing_location_prints_a_question_mark(self) -> None:
        tree = _tree(_case("A/testB()", _failure("crashed")))
        self.assertEqual(failures_from_tree(tree, ROOT)[0]["location"], "?")

    def test_path_outside_the_repo_stays_absolute(self) -> None:
        tree = _tree(_case("A/testB()", _failure("x", "/elsewhere/A.swift", 1)))
        self.assertEqual(failures_from_tree(tree, ROOT)[0]["location"], "/elsewhere/A.swift:1")

    def test_empty_or_unreadable_bundle_prints_nothing(self) -> None:
        self.assertEqual(failures_from_tree({}, ROOT), [])


class BuildReportTests(unittest.TestCase):
    TREE = _tree(
        _case("A/testFlaky()", _failure("timed out", "/repo/A.swift", 4)),
        _case("A/testFine()"),
        _case("A/testOff()", result="Skipped"),
    )

    def test_a_failed_run_lists_its_failures(self) -> None:
        report = build_report(self.TREE, 65, "ui-tests (rest)", ROOT)
        self.assertEqual([f["test"] for f in report["failures"]], ["A/testFlaky()"])
        self.assertEqual(report["retry_only_passes"], [])
        self.assertEqual((report["job"], report["rc"]), ("ui-tests (rest)", 65))

    def test_a_passed_run_lists_its_failures_as_retry_only_passes(self) -> None:
        report = build_report(self.TREE, 0, "ui-tests (rest)", ROOT)
        self.assertEqual(report["failures"], [])
        self.assertEqual([f["location"] for f in report["retry_only_passes"]], ["A.swift:4"])

    def test_without_an_exit_code_failures_stay_failures(self) -> None:
        self.assertEqual(len(build_report(self.TREE, None, "unit-tests", ROOT)["failures"]), 1)

    def test_counts_each_result_and_the_total(self) -> None:
        self.assertEqual(counts_from_tree(self.TREE), {"total": 3, "passed": 2, "skipped": 1})
        self.assertEqual(counts_from_tree({}), {"total": 0})


if __name__ == "__main__":
    unittest.main()
