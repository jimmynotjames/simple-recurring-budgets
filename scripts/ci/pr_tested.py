#!/usr/bin/env python3
"""Decide whether a push to main carries code its PR's CI already tested, so ci.yml can skip
the macOS work on main.

Prints `code=false` when every check below holds, else `code=true` (the build and tests run):
  1. The pushed commit is the merge commit of a merged PR (`merge_commit_sha` == the pushed SHA).
  2. The pushed commit's tree equals the PR head's tree.
  3. Main before the push (`before`) is an ancestor of the PR head, i.e. the PR was up to date.
     A pull_request run tests the PR head merged into main as it was then, and main only moves
     forward (the ruleset blocks non-fast-forward pushes), so that merge had the head's tree too.
  4. An automatic `pull_request` run of this workflow on the PR head concluded `success`. Manual
     runs don't count: a narrowed `/ci` run can pass without running the tests.
Any API error, or a fact that can't be read, prints `code=true`: unknown means the tests run.
A short reason goes to stderr for the job log.

Reads GITHUB_REPOSITORY, GITHUB_SHA, CI_BEFORE (the push's `before`) and CI_WORKFLOW (the
workflow file name, e.g. ci.yml) from the environment. Uses the `gh` CLI, authenticated by
GH_TOKEN with contents:read, pull-requests:read and actions:read.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections.abc import Callable

Api = Callable[[str], object]


def gh_api(path: str) -> object:
    out = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def tree(api: Api, repo: str, sha: str) -> str:
    return api(f"repos/{repo}/git/commits/{sha}")["tree"]["sha"]  # type: ignore[index]


def decide(api: Api, repo: str, sha: str, before: str, workflow: str) -> tuple[bool, str]:
    """Return (already_tested, reason)."""
    if not (repo and sha and before and workflow) or set(before) == {"0"}:
        return False, "missing push details"
    pulls = api(f"repos/{repo}/commits/{sha}/pulls")
    pr = next((p for p in pulls if p.get("merged_at") and p.get("merge_commit_sha") == sha), None)  # type: ignore[union-attr]
    if pr is None:
        return False, f"{sha[:7]} is not a PR's merge commit"
    number, head = pr["number"], pr["head"]["sha"]
    if tree(api, repo, sha) != tree(api, repo, head):
        return False, f"PR #{number}'s head {head[:7]} has a different tree than {sha[:7]}"
    status = api(f"repos/{repo}/compare/{before}...{head}")["status"]  # type: ignore[index]
    if status not in ("ahead", "identical"):
        return False, f"PR #{number} was not up to date with main (compare: {status})"
    runs = api(
        f"repos/{repo}/actions/workflows/{workflow}/runs"
        f"?event=pull_request&head_sha={head}&status=success&per_page=1"
    )
    if not runs.get("total_count"):  # type: ignore[union-attr]
        return False, f"no successful pull_request run on PR #{number}'s head {head[:7]}"
    return True, f"PR #{number}'s CI already passed on this exact code ({head[:7]})"


def main() -> int:
    env = os.environ
    try:
        tested, reason = decide(
            gh_api, env.get("GITHUB_REPOSITORY", ""), env.get("GITHUB_SHA", ""),
            env.get("CI_BEFORE", ""), env.get("CI_WORKFLOW", ""),
        )
    except Exception as error:  # noqa: BLE001 - any failure means run the tests
        tested, reason = False, f"could not check ({error})"
    print(f"pr_tested: {reason}", file=sys.stderr)
    print(f"code={'false' if tested else 'true'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
