"""A repeated `make focused-tests` run tallies to one line naming each test that failed and how often."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from tally_iterations import summary_line, tally  # noqa: E402


def case(test_id: str, *runs: str, result: str = "Passed") -> dict:
    return {
        "nodeType": "Test Case",
        "nodeIdentifier": test_id,
        "result": result,
        "children": [{"nodeType": "Repetition", "result": r} for r in runs],
    }


def tree(*cases: dict) -> dict:
    suite = {"nodeType": "Test Suite", "children": list(cases)}
    return {"testNodes": [{"nodeType": "Test Plan", "children": [{"nodeType": "UI test bundle", "children": [suite]}]}]}


class TallyTests(unittest.TestCase):
    def test_all_repetitions_passing(self) -> None:
        results = tally(tree(case("A/testOne", "Passed", "Passed"), case("A/testTwo", "Passed", "Passed")))
        self.assertEqual(summary_line(results), "Tally: 4 of 4 test runs passed (2 tests).")

    def test_a_flaky_test_is_named_with_its_failure_count(self) -> None:
        results = tally(
            tree(
                case("A/testOne", "Passed", "Failed", "Passed", "Failed", "Passed", result="Failed"),
                case("A/testTwo", *["Passed"] * 5),
            )
        )
        self.assertEqual(
            summary_line(results),
            "Tally: 8 of 10 test runs passed (2 tests). `A/testOne` failed 2 of 5.",
        )

    def test_a_single_run_counts_the_test_case_itself(self) -> None:
        results = tally(tree(case("A/testOne", result="Failed")))
        self.assertEqual(
            summary_line(results), "Tally: 0 of 1 test runs passed (1 test). `A/testOne` failed 1 of 1."
        )

    def test_a_parameterized_test_counts_repetitions_under_its_arguments(self) -> None:
        argument = lambda *runs: {  # noqa: E731
            "nodeType": "Arguments",
            "children": [{"nodeType": "Repetition", "result": r} for r in runs],
        }
        parameterized = {
            "nodeType": "Test Case",
            "nodeIdentifier": "S/check(value:)",
            "result": "Failed",
            "children": [argument("Passed", "Passed"), argument("Passed", "Failed")],
        }
        self.assertEqual(
            summary_line(tally(tree(parameterized))),
            "Tally: 3 of 4 test runs passed (1 test). `S/check(value:)` failed 1 of 4.",
        )

    def test_skipped_runs_are_called_out(self) -> None:
        self.assertEqual(
            summary_line(tally(tree(case("A/testOne", "Passed", "Skipped")))),
            "Tally: 1 of 2 test runs passed (1 test). 1 neither passed nor failed (skipped or expected failures).",
        )

    def test_an_empty_bundle(self) -> None:
        self.assertEqual(summary_line(tally({})), "Tally: no test results in the bundle.")


if __name__ == "__main__":
    unittest.main()
