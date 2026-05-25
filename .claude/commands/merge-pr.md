---
description: After review, squash-merge a PR, delete its branch, and close or annotate the linked issue (back half of the issue-driven workflow).
argument-hint: <pr-number>
---

The PR #$1 has been reviewed and approved to land. Execute the **Issue-driven workflow** back half from `AGENTS.md`:

1. Confirm it's safe to merge: `gh pr view $1` and `gh pr checks $1`. If checks are failing or it isn't approved/mergeable, stop and report instead of merging.
2. Identify the linked issue from the PR body's `Closes #N` / `Refs #N` reference, and note whether it's a complete fix (`Closes`) or partial (`Refs`).
3. Squash-merge: `gh pr merge $1 --squash`. One PR = one commit on `main`.
4. Clean up **both** branches — deleting only the remote leaves a stale local branch:
   - Remote: `gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch> -X DELETE`.
   - Local: `git checkout main && git pull --ff-only && git branch -D <branch>` (`-D`, since a squash-merge leaves the local tip un-ancestored).
   - Stale tracking ref: `git fetch --prune` (clears the `origin/<branch>` ref that `git pull --ff-only` leaves behind).
5. Resolve the linked issue:
   - **Complete fix** — verify it auto-closed with `gh issue view <N> --json state,stateReason`. If still open, close explicitly: `gh issue close <N> --comment "Fixed in #$1."`.
   - **Partial fix** — leave it open and comment a pointer: `gh issue comment <N> --body "Partially addressed by #$1. Still pending: <summary>."`.
6. Report what merged, that the branch was deleted, and the final issue state.
