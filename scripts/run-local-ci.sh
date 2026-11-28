#!/usr/bin/env bash
# Run the unit and UI suites on this machine in place of CI's macOS jobs, then mark the commit
# `local-tests-passed` so ci.yml skips the build and tests for it (AGENTS.md §CI). The Linux gates
# (lint, secrets, check-large-files, i18n-gates, tooling) still run on CI.
#
# Run it on the branch to test, with or without an open PR (the /run-local-ci skill drives it):
#   1. Cancels the PR's unfinished CI runs: this run replaces them, and they hold macOS runners.
#   2. Rebases the branch on the latest origin/main. A conflict stops it with the branch as it was.
#   3. Runs `make tests` (unit, then UI) with UI_WORKERS=2 unless set; the simulator-slots pool
#      grants what is free. A failure stops it and pushes nothing.
#   4. Pushes the commit to a side ref (no workflow runs on it), sets the `local-tests-passed`
#      status on it, then force-pushes the branch (with a lease) and deletes the side ref. The mark
#      is on the commit before the branch moves, so the PR run's `changes` job always sees it.
# Any later commit has no mark, so its PR run tests it in full.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTEXT=local-tests-passed
die() { echo "run-local-ci: $*" >&2; exit 1; }
say() { echo "run-local-ci: $*"; }

branch="$(git symbolic-ref --quiet --short HEAD)" || die "HEAD is detached; check out the PR's branch"
[[ "$branch" != main ]] || die "on main; check out the branch to test"
[[ -z "$(git status --porcelain)" ]] || die "uncommitted changes; commit or stash them first"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
pr="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"

# 1. Cancel the PR's unfinished CI runs.
if [[ -n "$pr" ]]; then
    for id in $(gh run list --workflow ci.yml --branch "$branch" --event pull_request --limit 20 \
        --json databaseId,status --jq '.[] | select(.status != "completed") | .databaseId'); do
        say "cancelling CI run $id on PR #$pr"
        gh run cancel "$id" >/dev/null || say "could not cancel run $id (it may have just finished)"
    done
fi

# 2. Rebase. --force-rebase rewrites the commits even when already up to date, so the push below is
# always a new commit whose PR run starts after the mark is set.
git fetch --quiet origin
remote_before="$(git rev-parse --quiet --verify "refs/remotes/origin/${branch}" || true)"
if ! git rebase --quiet --force-rebase origin/main; then
    git rebase --abort
    die "rebasing on origin/main conflicts; resolve it by hand, then run this again"
fi
sha="$(git rev-parse HEAD)"
say "testing ${branch}@${sha:0:7} (rebased on origin/main $(git rev-parse --short origin/main))"

# 3. Unit, then UI.
export UI_WORKERS="${UI_WORKERS:-2}"
if ! make tests; then
    die "tests failed on ${sha:0:7}; nothing was pushed or marked (the rebase is local only)"
fi

# 4. Mark, then push.
side="refs/local-tests/${sha}"
trap 'git push --quiet origin --delete "$side" 2>/dev/null || true' EXIT
git push --quiet origin "${sha}:${side}"
gh api "repos/${repo}/statuses/${sha}" -f state=success -f context="$CONTEXT" \
    -f description="Unit and UI tests passed locally (scripts/run-local-ci.sh)" >/dev/null
if [[ -n "$remote_before" ]]; then
    git push --quiet --force-with-lease="${branch}:${remote_before}" -u origin "HEAD:refs/heads/${branch}"
else
    git push --quiet -u origin "HEAD:refs/heads/${branch}"
fi
say "passed: marked ${sha:0:7} ${CONTEXT} and pushed ${branch}${pr:+ (PR #$pr)}"
