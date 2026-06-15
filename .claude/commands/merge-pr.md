---
description: After review, squash-merge a PR, delete its branch, and close or annotate any linked issue. Works with PRs opened by /create-pr-for-issue (issue-linked) and /create-pr (no issue required).
argument-hint: <pr-number>
---

The PR #$1 has been reviewed and approved to land.

1. Wait for CI, then confirm it's safe to merge: `gh pr view $1` and `gh pr checks $1`. If any check is still pending/queued, wait for completion with `gh pr checks $1 --watch` run **in the background** (the harness re-invokes you when it finishes; never a hand-rolled sleep loop). This is the **only** CI gate — `main` has no GitHub branch protection, so `gh pr merge` would happily land a red or still-running PR. If checks are failing or it isn't approved/mergeable, stop and report instead of merging.
2. Scan the PR body for issue linkage via `gh pr view $1 --json body --jq '.body'`: look for `Closes #N` (complete fix) or `Refs #N` (partial). If neither is present, this is a no-issue PR (e.g. from `/create-pr`) — note that and skip step 7.
3. **Pre-merge OpenSpec check** — skip this step if the PR diff contains no changes under `openspec/`. If OpenSpec files are touched: confirm any associated change is fully done. It's **either** already archived (delta specs synced into `openspec/specs/`, change moved under `openspec/changes/archive/`) **or** intentionally deferred to now. Verify with `openspec list` and the PR diff. If archiving — or any other OpenSpec step (unsynced delta specs, incomplete tasks/artifacts) — is **still pending**, do NOT merge: stop, tell the user exactly which step is pending, and ask whether to complete it now. If yes, do it on **this PR's branch** (check out the branch, sync + `/opsx:archive <name>`, push so it lands in the same PR), then continue. Don't merge with pending OpenSpec work unless the user explicitly says to merge anyway.
4. **Check for spec drift from workshopping** — skip this step if step 3 was skipped (no OpenSpec in the PR). If the PR was workshopped after the change was archived (review-time changes to behavior, specs, or the data model that the already-archived/synced specs don't reflect), **stop and ask** the user whether to update the OpenSpec docs and re-sync the main specs before merging. Edit the change in place under `openspec/changes/archive/<…>/` and re-run the spec sync; it all stays in this same PR.
5. Squash-merge: `gh pr merge $1 --squash`. One PR = one commit on `main`.
6. Clean up **both** branches — deleting only the remote leaves a stale local branch:
   - Remote: `gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch> -X DELETE`.
   - Local: `git checkout main && git pull --ff-only && git branch -D <branch>` (`-D`, since a squash-merge leaves the local tip un-ancestored).
   - Stale tracking ref: `git fetch --prune` (clears the `origin/<branch>` ref that `git pull --ff-only` leaves behind).
7. Resolve the linked issue (skip if step 2 found no issue):
   - **Complete fix** (`Closes #N`) — verify it auto-closed with `gh issue view <N> --json state,stateReason`. If still open, close explicitly: `gh issue close <N> --comment "Fixed in #$1."`.
   - **Partial fix** (`Refs #N`) — leave it open and comment a pointer: `gh issue comment <N> --body "Partially addressed by #$1. Still pending: <summary>."`.
8. Report what merged, that the branch was deleted, the final issue state (or "no linked issue"), and any OpenSpec outcome — or, if applicable, that the user chose to merge with something still pending.
