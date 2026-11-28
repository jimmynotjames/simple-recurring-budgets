"""The CI summary finds the run's PR, renders every job and failure, and posts without failing CI."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

import ci_summary as cs  # noqa: E402


class FakeGh:
    """Answers each gh call by the first matching argument fragment; records every call."""

    def __init__(self, answers: dict[str, str | Exception]) -> None:
        self.answers = answers
        self.calls: list[tuple[list[str], str | None]] = []

    def __call__(self, args: list[str], stdin: str | None = None) -> str:
        self.calls.append((args, stdin))
        for fragment, answer in self.answers.items():
            if any(fragment in a for a in args):
                if isinstance(answer, Exception):
                    raise answer
                return answer
        return ""


def _ctx(event: str, **overrides) -> dict:
    env = {"GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "7", "GITHUB_EVENT_NAME": event,
           "GITHUB_SHA": "abcdef1234567", "GITHUB_REF_NAME": overrides.pop("ref", "main")}
    env.update(overrides.pop("env", {}))
    return cs.load_context(env, overrides.pop("payload", {}))


class ResolvePrTests(unittest.TestCase):
    def test_pull_request_uses_its_own_number(self) -> None:
        ctx = _ctx("pull_request", payload={"pull_request": {"number": 12, "head": {"ref": "b"}}})
        self.assertEqual(cs.resolve_pr(ctx, FakeGh({})), "12")

    def test_dispatch_uses_the_pr_input(self) -> None:
        gh = FakeGh({})
        self.assertEqual(cs.resolve_pr(_ctx("workflow_dispatch", payload={"inputs": {"pr": "40"}}), gh), "40")
        self.assertEqual(gh.calls, [])

    def test_dispatch_without_input_finds_the_branch_pr(self) -> None:
        gh = FakeGh({"list": "41\n"})
        self.assertEqual(cs.resolve_pr(_ctx("workflow_dispatch", ref="feature"), gh), "41")
        self.assertIn("feature", gh.calls[0][0])

    def test_dispatch_on_a_branch_with_no_pr_has_none(self) -> None:
        self.assertEqual(cs.resolve_pr(_ctx("workflow_dispatch", ref="feature"), FakeGh({"list": ""})), "")

    def test_push_uses_the_commit_pr(self) -> None:
        gh = FakeGh({"/pulls": "435\n"})
        self.assertEqual(cs.resolve_pr(_ctx("push"), gh), "435")
        self.assertIn("repos/o/r/commits/abcdef1234567/pulls", gh.calls[0][0])

    def test_push_falls_back_to_the_subject_number(self) -> None:
        payload = {"head_commit": {"message": "Fixed it. (#434)\n\nbody (#1)"}}
        for answer in ("", cs.GhError("boom")):
            self.assertEqual(cs.resolve_pr(_ctx("push", payload=payload), FakeGh({"/pulls": answer})), "434")

    def test_push_with_no_pr_anywhere_has_none(self) -> None:
        payload = {"head_commit": {"message": "Direct push"}}
        self.assertEqual(cs.resolve_pr(_ctx("push", payload=payload), FakeGh({})), "")

    def test_other_events_have_none(self) -> None:
        self.assertEqual(cs.resolve_pr(_ctx("schedule"), FakeGh({})), "")


class TriggerTests(unittest.TestCase):
    def test_each_event_names_its_trigger(self) -> None:
        self.assertEqual(cs.describe_trigger(_ctx("pull_request")), "PR push")
        self.assertEqual(cs.describe_trigger(_ctx("push")), "push to main after merge")
        cmd = _ctx("workflow_dispatch", env={"CI_COMMAND": "/ci unit x3"})
        self.assertEqual(cs.describe_trigger(cmd), "`/ci unit x3`")
        manual = _ctx("workflow_dispatch", payload={"inputs": {"tests": "ui"}})
        self.assertEqual(cs.describe_trigger(manual), "manual dispatch (gates+build, tests=ui)")
        focused = _ctx("workflow_dispatch", payload={"inputs": {"test": "T/C", "iterations": "3", "pr": "5"}})
        self.assertEqual(cs.describe_trigger(focused), "`/ci` (gates+build, test=`T/C` x3)")


def _data(**overrides) -> dict:
    data = {
        "trigger": "PR push", "branch": "feat", "sha": "abcdef1234567", "run_id": "7",
        "run_url": "https://github.com/o/r/actions/runs/7", "code": "true",
        "jobs": [
            {"name": "build", "conclusion": "success", "seconds": 312},
            {"name": "ui-tests (editing)", "conclusion": "failure", "seconds": 1501},
            {"name": "focused-tests", "conclusion": "skipped", "seconds": None},
        ],
        "wall_seconds": 1900, "reports": [], "annotations": [], "tally": "", "bundles": [],
        "marker": cs.STICKY, "flaky_log": None,
    }
    data.update(overrides)
    return data


class RenderTests(unittest.TestCase):
    def test_header_and_job_table(self) -> None:
        body = cs.render(_data())
        self.assertTrue(body.startswith(cs.STICKY + "\n### ❌ CI failed"))
        self.assertIn("PR push · `feat@abcdef1` · [run 7](https://github.com/o/r/actions/runs/7)", body)
        self.assertIn("wall-clock 31m 40s", body)
        self.assertIn("| ❌ | `ui-tests (editing)` | failure | 25m 01s |", body)
        self.assertIn("| ⏭️ | `focused-tests` | skipped | — |", body)
        self.assertNotIn("Docs-only", body)

    def test_verdicts(self) -> None:
        passed = [{"name": "a", "conclusion": "success", "seconds": 1}]
        self.assertIn("✅ CI passed", cs.render(_data(jobs=passed)))
        cancelled = passed + [{"name": "b", "conclusion": "cancelled", "seconds": 1}]
        self.assertIn("🚫 CI cancelled", cs.render(_data(jobs=cancelled)))
        failing = [{"job": "unit", "failures": [{"test": "T", "location": "?", "text": "x"}]}]
        self.assertIn("❌ CI failed", cs.render(_data(jobs=passed, reports=failing)))

    def test_docs_only_note(self) -> None:
        self.assertIn("Docs-only change", cs.render(_data(code="false")))

    def test_already_tested_note_on_a_push(self) -> None:
        body = cs.render(_data(code="false", event="push"))
        self.assertIn("Already tested", body)
        self.assertNotIn("Docs-only", body)

    def test_tested_locally_note_on_a_marked_pr(self) -> None:
        body = cs.render(_data(code="false", event="pull_request", skip="local-tests-passed"))
        self.assertIn("Tested locally", body)
        self.assertNotIn("Docs-only", body)

    def test_failures_retries_annotations_tally_and_bundles(self) -> None:
        reports = [{
            "job": "ui-tests-editing", "counts": {"total": 40, "passed": 39, "failed": 1},
            "failures": [{"test": "C/testA()", "location": "UI/C.swift:12", "text": "not\nfound"}],
            "retry_only_passes": [{"test": "C/testB()", "location": "UI/C.swift:30", "text": "slow"}],
        }]
        annotations = [{"job": "lint", "level": "failure", "path": "A.swift", "line": 3,
                        "title": "SwiftLint", "message": "too long"}]
        body = cs.render(_data(reports=reports, annotations=annotations, tally="Tally: 3 of 3 passed.",
                               bundles=[{"name": "xcresults-ui-tests-editing", "url": "u/1"}],
                               flaky_log="UI/FLAKY_TESTS.md"))
        self.assertIn("- **ui-tests-editing**: 40 total, 39 passed, 1 failed", body)
        self.assertIn("#### Failed tests\n\n- **ui-tests-editing** `C/testA()` at `UI/C.swift:12`: not found",
                      body)
        self.assertIn("log each one in the flaky-test log (`UI/FLAKY_TESTS.md`)", body)
        self.assertIn("`C/testB()` at `UI/C.swift:30`: slow", body)
        self.assertIn("- ❌ **lint** `A.swift:3` SwiftLint: too long", body)
        self.assertIn("#### Focused tally\n\nTally: 3 of 3 passed.", body)
        self.assertIn("- [xcresults-ui-tests-editing](u/1)", body)

    def test_long_output_is_capped_with_a_note(self) -> None:
        many = [{"test": f"C/test{i}()", "location": "C.swift:1", "text": "x" * 300} for i in range(500)]
        body = cs.render(_data(reports=[{"job": "unit", "failures": many}], tally="Tally"))
        self.assertLessEqual(len(body), cs.CAP)
        self.assertIn("more lines not shown", body)
        self.assertIn("#### Focused tally\n\n_Not shown", body)


class DataTests(unittest.TestCase):
    def test_job_rows_drop_the_summary_job_and_time_each_job(self) -> None:
        raw = [{"id": 1, "name": "build", "conclusion": "success",
                "started_at": "2026-01-01T00:00:00Z", "completed_at": "2026-01-01T00:05:00Z"},
               {"id": 2, "name": "summary", "status": "in_progress"}]
        rows = cs.job_rows(raw, "summary")
        self.assertEqual([(r["name"], r["seconds"]) for r in rows], [("build", 300.0)])
        self.assertEqual(cs.wall_seconds(rows), 300.0)

    def test_skipped_matrix_job_drops_its_unexpanded_suffix(self) -> None:
        raw = [{"id": 1, "name": "ui-tests (${{ matrix.shard }})", "conclusion": "skipped"},
               {"id": 2, "name": "ui-tests (editing)", "conclusion": "success"}]
        self.assertEqual([r["name"] for r in cs.job_rows(raw, "summary")],
                         ["ui-tests", "ui-tests (editing)"])

    def test_annotations_keep_failures_first_and_at_most_twenty(self) -> None:
        found = ([{"level": "warning", "n": i} for i in range(15)] + [{"level": "notice"}]
                 + [{"level": "failure", "n": i} for i in range(10)])
        picked = cs.pick_annotations(found)
        self.assertEqual(len(picked), 20)
        self.assertEqual([a["level"] for a in picked[:10]], ["failure"] * 10)

    def test_reports_load_from_nested_artifact_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp, "test-report-unit-tests")
            folder.mkdir()
            (folder / "test-report-unit-tests.json").write_text(json.dumps({"failures": []}))
            (folder / "other.json").write_text("{}")
            self.assertEqual(cs.load_reports(tmp), [{"failures": [], "job": "unit-tests"}])
        self.assertEqual(cs.load_reports(None), [])


class PostTests(unittest.TestCase):
    def test_sticky_comment_is_edited_in_place(self) -> None:
        gh = FakeGh({"/issues/12/comments": "99\n"})
        self.assertEqual(cs.post_comment("o/r", "12", "body", True, gh), "updated")
        self.assertEqual(gh.calls[1][0][:3], ["api", "-X", "PATCH"])
        self.assertIn("repos/o/r/issues/comments/99", gh.calls[1][0])
        self.assertEqual(json.loads(gh.calls[1][1]), {"body": "body"})

    def test_sticky_comment_is_created_when_missing(self) -> None:
        gh = FakeGh({})
        self.assertEqual(cs.post_comment("o/r", "12", "body", True, gh), "posted")
        self.assertEqual(gh.calls[-1][0][:3], ["api", "-X", "POST"])

    def test_event_runs_always_post_a_new_comment(self) -> None:
        gh = FakeGh({"/issues/12/comments": "99\n"})
        self.assertEqual(cs.post_comment("o/r", "12", "body", False, gh), "posted")
        self.assertEqual(len(gh.calls), 1)

    def test_event_marker_is_not_the_sticky_marker(self) -> None:
        self.assertNotIn(cs.STICKY, cs.EVENT_MARK)

    def test_main_writes_the_summary_and_survives_a_failed_post(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            event = Path(tmp, "event.json")
            pr = {"number": 3, "head": {"ref": "b", "sha": "1234567"}}
            event.write_text(json.dumps({"pull_request": pr}))
            summary = Path(tmp, "summary.md")
            env = {"GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "7", "GITHUB_EVENT_NAME": "pull_request",
                   "GITHUB_EVENT_PATH": str(event), "GITHUB_STEP_SUMMARY": str(summary)}
            gh = FakeGh({"-X": cs.GhError("Resource not accessible by integration")})
            self.assertEqual(cs.main(["post", "--reports", tmp], env, gh), 0)
            self.assertIn("`b@1234567`", summary.read_text())


if __name__ == "__main__":
    unittest.main()
