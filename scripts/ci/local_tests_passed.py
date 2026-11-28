#!/usr/bin/env python3
"""Decide whether a PR's head commit already passed the unit and UI tests locally, so ci.yml can
skip the macOS work for it.

scripts/run-local-ci.sh runs the full suites on the owner's machine and, on a pass, sets a
`local-tests-passed` commit status on the commit before the branch points at it. Prints
`code=false` only when the newest `local-tests-passed` status on the commit is `success` and was
set by the repository owner; else `code=true` (the build and tests run). Statuses set by anyone
else, including this workflow's own token, don't count. Any API error prints `code=true`.
A short reason goes to stderr for the job log.

Reads GITHUB_REPOSITORY, GITHUB_REPOSITORY_OWNER and CI_HEAD_SHA (the PR head) from the
environment. Uses the `gh` CLI, authenticated by GH_TOKEN with statuses:read.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections.abc import Callable

Api = Callable[[str], object]
CONTEXT = "local-tests-passed"


def gh_api(path: str) -> object:
    out = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def decide(api: Api, repo: str, sha: str, owner: str) -> tuple[bool, str]:
    """Return (tested_locally, reason)."""
    if not (repo and sha and owner):
        return False, "missing run details"
    statuses = api(f"repos/{repo}/commits/{sha}/statuses?per_page=100")
    # The API lists a commit's statuses newest first; the newest one per context is the live one.
    mark = next((s for s in statuses if s.get("context") == CONTEXT), None)  # type: ignore[union-attr]
    if mark is None:
        return False, f"{sha[:7]} has no {CONTEXT} mark"
    setter = (mark.get("creator") or {}).get("login")
    if setter != owner:
        return False, f"{sha[:7]}'s {CONTEXT} mark was set by {setter}, not the owner {owner}"
    if mark.get("state") != "success":
        return False, f"{sha[:7]}'s {CONTEXT} mark is {mark.get('state')}"
    return True, f"{sha[:7]} passed the unit and UI tests locally ({CONTEXT}, set by {owner})"


def main() -> int:
    env = os.environ
    try:
        tested, reason = decide(
            gh_api, env.get("GITHUB_REPOSITORY", ""), env.get("CI_HEAD_SHA", ""),
            env.get("GITHUB_REPOSITORY_OWNER", ""),
        )
    except Exception as error:  # noqa: BLE001 - any failure means run the tests
        tested, reason = False, f"could not check ({error})"
    print(f"local_tests_passed: {reason}", file=sys.stderr)
    print(f"code={'false' if tested else 'true'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
