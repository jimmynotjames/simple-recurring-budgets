#!/usr/bin/env python3
"""Print one `TEST-FAILED: <test id> <file:line> <failure text>` line per failure in a test run.

Report-only: never changes the run's outcome. Reads the bundle's per-test tree rather than its
summary, because only the tree carries each failure's file:line.

Usage: python3 scripts/list_test_failures.py [--json PATH [--rc N] [--job NAME]] <path-to.xcresult>

--json also writes the test-report JSON that scripts/ci/ci_summary.py reads:
  {"job": NAME, "rc": N or null, "failures": [{"test", "location", "text"}],
   "retry_only_passes": [...same...], "counts": {"total": n, "passed": n, "failed": n, ...}}
With --rc 0 the run passed, so every failure in the bundle was a test that passed on retry, and
it is listed under retry_only_passes instead of failures.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PREFIX = "TEST-FAILED:"


def failures_from_tree(tree: dict, repo_root: Path = REPO_ROOT) -> list[dict]:
    """Every failure message in `xcresulttool get test-results tests` output, with its test case."""
    found: list[dict] = []

    def walk(node: dict, test_id: str | None) -> None:
        if node.get("nodeType") == "Test Case":
            test_id = node.get("nodeIdentifier") or node.get("name") or test_id
        if node.get("nodeType") == "Failure Message":
            found.append({
                "test": test_id or "?",
                "location": _location(node.get("sourceLocation"), repo_root),
                "text": " ".join((node.get("name") or "").split()),
            })
        for child in node.get("children") or []:
            walk(child, test_id)

    for root in tree.get("testNodes") or []:
        walk(root, None)
    return found


def counts_from_tree(tree: dict) -> dict[str, int]:
    """How many test cases ended with each result, plus their total."""
    counts: dict[str, int] = {}

    def walk(node: dict) -> None:
        if node.get("nodeType") == "Test Case":
            result = (node.get("result") or "unknown").lower().replace(" ", "_")
            counts[result] = counts.get(result, 0) + 1
            return
        for child in node.get("children") or []:
            walk(child)

    for root in tree.get("testNodes") or []:
        walk(root)
    return {"total": sum(counts.values()), **dict(sorted(counts.items()))}


def build_report(tree: dict, rc: int | None, job: str, repo_root: Path = REPO_ROOT) -> dict:
    found = failures_from_tree(tree, repo_root)
    passed = rc == 0
    return {
        "job": job,
        "rc": rc,
        "failures": [] if passed else found,
        "retry_only_passes": found if passed else [],
        "counts": counts_from_tree(tree),
    }


def _location(source: dict | None, repo_root: Path) -> str:
    if not source or not source.get("filePath"):
        return "?"
    path = Path(source["filePath"])
    try:
        path = path.relative_to(repo_root)
    except ValueError:
        pass
    line = source.get("lineNumber")
    return f"{path}:{line}" if line is not None else str(path)


def read_tree(bundle: str) -> dict:
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout:
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", help="Path to the run's .xcresult")
    parser.add_argument("--json", metavar="PATH", help="Also write the test-report JSON here")
    parser.add_argument("--rc", type=int, help="The test run's exit code (0: failures were retries)")
    parser.add_argument("--job", default="", help="The job name to record in the JSON")
    args = parser.parse_args(argv)

    tree = read_tree(args.bundle)
    for failure in failures_from_tree(tree):
        print(f"{PREFIX} {failure['test']} {failure['location']} {failure['text']}")
    if args.json:
        job = args.job or Path(args.json).stem.removeprefix("test-report-")
        report = build_report(tree, args.rc, job)
        Path(args.json).write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
