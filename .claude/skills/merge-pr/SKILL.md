---
name: merge-pr
description: Wait for a reviewed PR's required CI checks, squash-merge it, delete its branch, and close or annotate any linked issue. Runs no local gate or tests. Works with PRs opened by /create-pr-for-issue (issue-linked) and /create-pr (no issue required). Invoked via /merge-pr <PR>.
---

# Merge a reviewed PR

Use when the user asks to merge an existing, reviewed PR and clean up its branches.
Resolve the requested PR number as `<PR>` below. The user must authorize the merge;
a request to inspect or review a PR alone is not authorization.

1. **Verify it's safe to merge.** Run `gh pr view <PR>` and confirm it is `OPEN` and `MERGEABLE`.

   Wait for the required CI checks (AGENTS.md § CI), in the background:

   ```bash
   gh pr checks <PR> --required --watch
   ```

   `tests` is one of them; a docs-only PR's `tests` passes without running anything.

   **The watch can return before `tests` exists.** It only watches checks already reported, and
   `tests` reports once `build` and the test jobs finish. So after it returns, confirm every
   required check is present and passed:

   ```bash
   gh pr checks <PR> --json name,bucket --jq '.[] | "\(.name) \(.bucket)"'
   ```

   It must list `lint`, `secrets`, `check-large-files`, `i18n-gates`, `tooling` and `tests`, each
   `pass`. If one is missing or `pending`, wait again (`--watch` in the background) and re-check.

   **If any fails, do NOT merge** — report it and stop. If the latest checks came from a narrowed
   `/ci` run rather than the automatic one, they can read green over a failure (AGENTS.md § CI):
   rerun the automatic run first.

   No local gate or tests: CI runs everything `make gate` does (the `tooling` job covers the
   script tests) plus the unit and UI suites (AGENTS.md § "Build and test").

2. **Scan the PR body for issue linkage** via `gh pr view <PR> --json body --jq '.body'`: look for
   `Closes #N` (complete fix) or `Refs #N` (partial). If neither is present, this is a no-issue PR
   (e.g. from `/create-pr`) — note that and skip step 7.

3. **Pre-merge OpenSpec check.** Skip if the PR diff has no changes under `openspec/`. Otherwise
   confirm any associated change is fully done: either already archived (delta specs synced into
   `openspec/specs/`, change moved under `openspec/changes/archive/`) or intentionally deferred to
   now. Verify with `openspec list` and the PR diff. If archiving or any other OpenSpec step
   (unsynced delta specs, incomplete tasks/artifacts) is still pending, do NOT merge: stop, tell the
   user exactly which step is pending, and ask whether to complete it now. If yes, do it on this
   PR's branch (check out the branch, sync + `/openspec-archive-change <name>`, push so it lands in the same
   PR), then go back to step 1 for the new commit. Don't merge with pending OpenSpec work unless the
   user explicitly says to merge anyway.

4. **Check for spec drift from workshopping.** Skip if step 3 was skipped. If the PR was
   workshopped after the change was archived (review-time changes to behavior, specs, or the data
   model that the archived/synced specs don't reflect), stop and ask the user whether to update the
   OpenSpec docs and re-sync the main specs before merging. Edit the change in place under
   `openspec/changes/archive/<…>/` and re-run the spec sync; it all stays in this PR.

5. **Squash-merge:** record the head SHA the green checks ran on
   (`gh pr view <PR> --json headRefOid --jq .headRefOid`), then run
   `gh pr merge <PR> --squash --match-head-commit <SHA>`, so a push after the checks can't land
   unchecked. One PR = one commit on `main`. Never merge on the same turn the PR was opened.

6. **Clean up branches.** The merge does not clean up after itself locally:
   - **Remote:** a 404 from `gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch>`
     means it is already gone; `-X DELETE` only if it still exists.
   - **Local:** `git checkout main && git pull --ff-only && git branch -D <branch>` (`-D`, since a
     squash-merge leaves the local tip un-ancestored).
   - **Stale tracking ref:** `git fetch --prune` (clears the `origin/<branch>` ref that
     `git pull --ff-only` leaves behind).
   - **Simulators:** run `make sim-shutdown` (AGENTS.md § "Simulator slots"). If this checkout is a
     worktree about to be removed, run `make sim-clean` instead (§ "Simulator sandbox").

7. **Resolve the linked issue** (skip if step 2 found none):
   - **Complete fix** (`Closes #N`): verify it auto-closed with
     `gh issue view <N> --json state,stateReason`. If still open, close it:
     `gh issue close <N> --comment "Fixed in #<PR>."`
   - **Partial fix** (`Refs #N`): leave it open and comment a pointer:
     `gh issue comment <N> --body "Partially addressed by #<PR>. Still pending: <summary>."`

8. **Report** what merged, the CI result, that the branch was deleted, that the simulators were
   shut down, the final issue state (or "no linked issue"), and any OpenSpec outcome, or that the
   user chose to merge with something still pending.
