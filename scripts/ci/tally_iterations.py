#!/usr/bin/env python3
"""Print one markdown line tallying a `make focused-tests` run's results across its iterations.

With `-test-iterations N` each Test Case node in the bundle has one Repetition node per run, nested
deeper for a parameterized test; without it the Test Case's own result is its one run.

Usage: python3 scripts/ci/tally_iterations.py <path-to.xcresult>
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from list_test_failures import read_tree  # noqa: E402


def tally(tree: dict) -> dict[str, Counter]:
    """Each test case's results, one per run: {test id: Counter({"Passed": 4, "Failed": 1})}."""
    found: dict[str, Counter] = {}

    def walk(node: dict) -> None:
        if node.get("nodeType") == "Test Case":
            test_id = node.get("nodeIdentifier") or node.get("name") or "?"
            runs = [r.get("result") or "?" for r in _repetitions(node)]
            found[test_id] = Counter(runs or [node.get("result") or "?"])
            return
        for child in node.get("children") or []:
            walk(child)

    for root in tree.get("testNodes") or []:
        walk(root)
    return found


def _repetitions(node: dict) -> list[dict]:
    found = []
    for child in node.get("children") or []:
        if child.get("nodeType") == "Repetition":
            found.append(child)
        else:
            found.extend(_repetitions(child))
    return found


def summary_line(results: dict[str, Counter]) -> str:
    if not results:
        return "Tally: no test results in the bundle."
    total = sum(sum(c.values()) for c in results.values())
    passed = sum(c["Passed"] for c in results.values())
    tests = f"{len(results)} test" + ("" if len(results) == 1 else "s")
    line = f"Tally: {passed} of {total} test runs passed ({tests})."
    failing = [
        f"`{test_id}` failed {c['Failed']} of {sum(c.values())}"
        for test_id, c in sorted(results.items())
        if c["Failed"]
    ]
    if failing:
        line += " " + "; ".join(failing) + "."
    neither = total - passed - sum(c["Failed"] for c in results.values())
    if neither:
        line += f" {neither} neither passed nor failed (skipped or expected failures)."
    return line


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", help="Path to the run's .xcresult")
    args = parser.parse_args(argv)
    print(summary_line(tally(read_tree(args.bundle))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
