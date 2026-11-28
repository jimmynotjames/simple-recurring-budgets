"""ci.yml skips the macOS work on a PR only when the owner marked its head `local-tests-passed`."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from local_tests_passed import CONTEXT, decide  # noqa: E402

REPO, SHA, OWNER = "o/r", "h" * 40, "owner"
PATH = f"repos/{REPO}/commits/{SHA}/statuses?per_page=100"


def status(state: str = "success", login: str = OWNER, context: str = CONTEXT) -> dict:
    return {"context": context, "state": state, "creator": {"login": login}}


def fake_api(statuses: list[dict]):
    calls = []

    def api(path: str):
        calls.append(path)
        return {PATH: statuses}[path]

    api.calls = calls  # type: ignore[attr-defined]
    return api


class LocalTestsPassedTests(unittest.TestCase):
    def test_owner_success_mark_is_tested(self) -> None:
        tested, reason = decide(fake_api([status(context="other"), status()]), REPO, SHA, OWNER)
        self.assertTrue(tested)
        self.assertIn(CONTEXT, reason)

    def test_no_mark_runs_the_tests(self) -> None:
        self.assertFalse(decide(fake_api([status(context="other")]), REPO, SHA, OWNER)[0])

    def test_mark_by_anyone_else_runs_the_tests(self) -> None:
        for login in ("github-actions[bot]", "someone"):
            with self.subTest(login=login):
                self.assertFalse(decide(fake_api([status(login=login)]), REPO, SHA, OWNER)[0])

    def test_newest_mark_wins(self) -> None:
        # Newest first: a later failure voids an earlier pass, and a later pass replaces a failure.
        self.assertFalse(decide(fake_api([status("failure"), status()]), REPO, SHA, OWNER)[0])
        self.assertTrue(decide(fake_api([status(), status("failure")]), REPO, SHA, OWNER)[0])

    def test_missing_details_run_the_tests_without_calling_the_api(self) -> None:
        for args in (("", SHA, OWNER), (REPO, "", OWNER), (REPO, SHA, "")):
            with self.subTest(args=args):
                api = fake_api([status()])
                self.assertFalse(decide(api, *args)[0])
                self.assertEqual(api.calls, [])  # type: ignore[attr-defined]


if __name__ == "__main__":
    unittest.main()
