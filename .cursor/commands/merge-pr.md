---
name: /merge-pr
id: merge-pr
category: Workflow
description: After review, squash-merge a PR, delete its branch, and close or annotate the linked issue (back half of the issue-driven workflow).
---

PR `#<PR>` (the PR number you pass to this command) has been reviewed and approved to land. Execute the **Issue-driven workflow** back half from `AGENTS.md`:

1. Confirm it's safe to merge: `gh pr view <PR>` and `gh pr checks <PR>`. If checks are failing or it isn't approved/mergeable, stop and report instead of merging.
2. Identify the linked issue from the PR body's `Closes #N` / `Refs #N` reference, and note whether it's a complete fix (`Closes`) or partial (`Refs`).
3. **Pre-merge OpenSpec check** — before merging, confirm any OpenSpec change tied to this PR is fully done. It's **either** already archived in this PR (delta specs synced into `openspec/specs/`, change moved under `openspec/changes/archive/`) **or** intentionally deferred to now (the front half held off archiving because confidence was incomplete — pending manual verification / complexity). Verify with `openspec list` and the PR diff. If archiving — or any other OpenSpec step (unsynced delta specs, incomplete tasks/artifacts) — is **still pending**, do NOT merge: stop, tell the user exactly which step is pending, and ask whether to complete it now (the expected path for a deferred archive). If yes, do it on **this PR's branch** (check out the branch, sync + `/opsx:archive <name>`, push so it lands in the same PR), then continue. Don't merge with pending OpenSpec work unless the user explicitly says to merge anyway.
4. **Check for spec drift from workshopping** — if the PR was workshopped after the change was archived (review-time changes to behavior, specs, or the data model that the already-archived/synced specs don't reflect), **stop and ask** the user whether to update the OpenSpec docs (the archived change's delta specs / design / tasks) and re-sync the main specs before merging, so the archived change and `openspec/specs/` match what's shipping. Edit the change in place under `openspec/changes/archive/<…>/` and re-run the spec sync; it all stays in this same PR.
5. Squash-merge: `gh pr merge <PR> --squash`. One PR = one commit on `main`.
6. Clean up **both** branches — deleting only the remote leaves a stale local branch:
   - Remote: `gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch> -X DELETE`.
   - Local: `git checkout main && git pull --ff-only && git branch -D <branch>` (`-D`, since a squash-merge leaves the local tip un-ancestored).
   - Stale tracking ref: `git fetch --prune` (clears the `origin/<branch>` ref that `git pull --ff-only` leaves behind).
7. Resolve the linked issue:
   - **Complete fix** — verify it auto-closed with `gh issue view <N> --json state,stateReason`. If still open, close explicitly: `gh issue close <N> --comment "Fixed in #<PR>."`.
   - **Partial fix** — leave it open and comment a pointer: `gh issue comment <N> --body "Partially addressed by #<PR>. Still pending: <summary>."`.
8. Report what merged, that the branch was deleted, the final issue state, and that the OpenSpec change was archived (and specs updated for any workshopping) in the PR — or, if applicable, that the user chose to merge with something still pending.
