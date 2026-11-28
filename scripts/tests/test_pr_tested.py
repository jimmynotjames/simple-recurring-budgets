"""ci.yml skips the macOS work on a push to main only when its PR's CI tested the same code."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from pr_tested import decide  # noqa: E402

REPO, SHA, BEFORE, HEAD, WF = "o/r", "m" * 40, "b" * 40, "h" * 40, "ci.yml"
RUNS = f"repos/{REPO}/actions/workflows/{WF}/runs?event=pull_request&head_sha={HEAD}&per_page=10"


def fake_api(**overrides):
    responses = {
        f"repos/{REPO}/commits/{SHA}/pulls": [
            {"number": 9, "merged_at": "2026-11-27T00:00:00Z", "merge_commit_sha": SHA,
             "head": {"sha": HEAD}},
        ],
        f"repos/{REPO}/git/commits/{SHA}": {"tree": {"sha": "t1"}},
        f"repos/{REPO}/git/commits/{HEAD}": {"tree": {"sha": "t1"}},
        f"repos/{REPO}/compare/{BEFORE}...{HEAD}": {"status": "ahead"},
        RUNS: {"workflow_runs": [{"id": 1}, {"id": 2}]},
        f"repos/{REPO}/actions/runs/1/jobs?per_page=100": {"jobs": [{"name": "tests", "conclusion": "failure"}]},
        f"repos/{REPO}/actions/runs/2/jobs?per_page=100": {"jobs": [
            {"name": "tests", "conclusion": "success"}, {"name": "summary", "conclusion": None},
        ]},
    }
    responses.update(overrides)
    calls = []

    def api(path: str):
        calls.append(path)
        return responses[path]

    api.calls = calls  # type: ignore[attr-defined]
    return api


class PrTestedTests(unittest.TestCase):
    def test_up_to_date_pr_that_passed_is_tested(self) -> None:
        tested, reason = decide(fake_api(), REPO, SHA, BEFORE, WF)
        self.assertTrue(tested)
        self.assertIn("PR #9", reason)

    def test_identical_compare_counts_as_up_to_date(self) -> None:
        api = fake_api(**{f"repos/{REPO}/compare/{BEFORE}...{HEAD}": {"status": "identical"}})
        self.assertTrue(decide(api, REPO, SHA, BEFORE, WF)[0])

    def test_no_merged_pr_runs_the_tests(self) -> None:
        for pulls in ([], [{"number": 9, "merged_at": None, "merge_commit_sha": SHA, "head": {"sha": HEAD}}],
                      [{"number": 9, "merged_at": "x", "merge_commit_sha": "other", "head": {"sha": HEAD}}]):
            with self.subTest(pulls=pulls):
                api = fake_api(**{f"repos/{REPO}/commits/{SHA}/pulls": pulls})
                self.assertFalse(decide(api, REPO, SHA, BEFORE, WF)[0])

    def test_different_tree_runs_the_tests(self) -> None:
        api = fake_api(**{f"repos/{REPO}/git/commits/{HEAD}": {"tree": {"sha": "t2"}}})
        self.assertFalse(decide(api, REPO, SHA, BEFORE, WF)[0])

    def test_pr_behind_main_runs_the_tests(self) -> None:
        for status in ("behind", "diverged"):
            with self.subTest(status=status):
                api = fake_api(**{f"repos/{REPO}/compare/{BEFORE}...{HEAD}": {"status": status}})
                self.assertFalse(decide(api, REPO, SHA, BEFORE, WF)[0])

    def test_passed_tests_job_counts_while_the_run_is_still_going(self) -> None:
        # Auto-merge lands the PR when `tests` passes; `summary` (conclusion None) is still running.
        self.assertTrue(decide(fake_api(), REPO, SHA, BEFORE, WF)[0])

    def test_no_passed_tests_job_runs_the_tests(self) -> None:
        for runs in ([], [{"id": 1}]):
            with self.subTest(runs=runs):
                api = fake_api(**{RUNS: {"workflow_runs": runs}})
                self.assertFalse(decide(api, REPO, SHA, BEFORE, WF)[0])

    def test_missing_push_details_run_the_tests_without_calling_the_api(self) -> None:
        for before in ("", "0" * 40):
            with self.subTest(before=before):
                api = fake_api()
                self.assertFalse(decide(api, REPO, SHA, before, WF)[0])
                self.assertEqual(api.calls, [])  # type: ignore[attr-defined]


if __name__ == "__main__":
    unittest.main()
