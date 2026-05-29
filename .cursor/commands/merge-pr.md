---
name: /merge-pr
id: merge-pr
category: Workflow
description: After review, squash-merge a PR, delete its branch, and close or annotate the linked issue (back half of the issue-driven workflow).
---

PR `#<PR>` (the PR number you pass to this command) has been reviewed and approved to land. Execute the **Issue-driven workflow** back half from `AGENTS.md`:

1. Confirm it's safe to merge: `gh pr view <PR>` and `gh pr checks <PR>`. If checks are failing or it isn't approved/mergeable, stop and report instead of merging.
2. Identify the linked issue from the PR body's `Closes #N` / `Refs #N` reference, and note whether it's a complete fix (`Closes`) or partial (`Refs`).
3. Squash-merge: `gh pr merge <PR> --squash`. One PR = one commit on `main`.
4. Clean up **both** branches — deleting only the remote leaves a stale local branch:
   - Remote: `gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch> -X DELETE`.
   - Local: `git checkout main && git pull --ff-only && git branch -D <branch>` (`-D`, since a squash-merge leaves the local tip un-ancestored).
   - Stale tracking ref: `git fetch --prune` (clears the `origin/<branch>` ref that `git pull --ff-only` leaves behind).
5. Resolve the linked issue:
   - **Complete fix** — verify it auto-closed with `gh issue view <N> --json state,stateReason`. If still open, close explicitly: `gh issue close <N> --comment "Fixed in #<PR>."`.
   - **Partial fix** — leave it open and comment a pointer: `gh issue comment <N> --body "Partially addressed by #<PR>. Still pending: <summary>."`.
6. Prompt about lingering OpenSpec steps: if this PR implemented an OpenSpec change, it stays active until archived. Run `openspec list`; if a change tied to this PR is still active (under `openspec/changes/<name>/`, not yet under `archive/`), **stop and ask** whether to finish it now (`/opsx:archive <name>` syncs delta specs into the main specs and moves the change to the archive) or defer. Always surface this — don't auto-archive silently or skip it. (Archiving lands spec edits on `main`, so it needs its own branch + PR.)
7. Report what merged, that the branch was deleted, the final issue state, and whether an OpenSpec archive is still pending.
