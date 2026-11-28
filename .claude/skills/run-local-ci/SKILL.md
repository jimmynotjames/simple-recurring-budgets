---
name: run-local-ci
description: Run the full unit and UI suites on this machine in place of CI's macOS jobs, mark the commit local-tests-passed, and push, so the PR's CI runs only the Linux gates. Works before /create-pr or on an open PR. Does not open, review or merge a PR. Invoked via /run-local-ci [<PR>].
---

# Run CI's tests locally

Use when the user asks to test a branch or PR locally instead of on CI's macOS runners. It drives
`make run-local-ci` (`scripts/run-local-ci.sh`), which:

1. cancels the PR's unfinished CI runs (they hold macOS runners and this run replaces them);
2. rebases the branch on the latest `origin/main`;
3. runs `make tests` (unit, then UI) with `UI_WORKERS=2`; the simulator-slots pool grants what is free;
4. on a pass, sets the `local-tests-passed` commit status on the rebased commit, then force-pushes
   the branch with a lease. The PR's CI run then skips `build` and the test jobs, and the required
   `tests` check passes on the mark (`scripts/ci/local_tests_passed.py`). The Linux gates still run.

## Steps

1. **Pick the branch.** With `<PR>`, check out its branch (`gh pr checkout <PR>`); without one, use
   the current branch. Stop and tell the user if the tree has uncommitted changes or HEAD is `main`.
   Before `/create-pr`, the branch needn't be pushed yet.
2. **Run it in the background.** `make run-local-ci` with `run_in_background`: a full run takes
   longer than a foreground command may. Don't poll; wait for the completion notice.
3. **Report.**
   - Pass: the commit marked, the branch pushed, and the PR (if any) whose CI now runs only the
     Linux gates. Auto-merge, if set, proceeds as usual.
   - Rebase conflict: nothing changed. Say which files conflict and stop.
   - Test failure: nothing was pushed or marked, and the local branch is now rebased. Name the
     failing tests from the output. A pass only on retry, or a failure in a test listed in the UI
     target's `FLAKY_TESTS.md`, is a flake: log it per that file. Don't rerun unless the user asks.

## Notes

- Any commit after the marked one has no mark, so its PR run tests it in full. If `/create-pr`
  then adds commits (review or gate fixes), CI tests that head in full; run `/run-local-ci` again
  on the PR to skip it.
- The mark is a commit status set with the owner's `gh` token. `ci.yml` honours it only when the
  repository owner set it; a mark from anyone else, or from the workflow's own token, is ignored.
- Merging still waits for every required check; this skill never merges.
