---
name: appstore-push-testflight-build
description: Build and ship a TestFlight build end-to-end — creates a release branch, runs `fastlane ios beta` (auto-bumps build number from ASC, archives, uploads, auto-commits the pbxproj bump), then pushes, opens a chore PR, waits for CI, and squash-merges. Use when cutting a new TestFlight build. Invoked via /appstore:push-testflight-build.
---

# Push a TestFlight build

Automates the full TestFlight release cut: **branch → build → upload → commit → PR → CI → merge**.

The `fastlane ios beta` lane handles the heavy lifting: it queries App Store Connect for the next build number, bumps `CURRENT_PROJECT_VERSION` in `project.pbxproj`, archives and exports the `.ipa`, uploads it to TestFlight (without waiting for Apple to process it), and auto-commits the pbxproj change. This skill wraps that with branch discipline, the PR + CI wait, and the squash-merge.

## Progress checklist

Print this unchecked at the start; re-print with `- [x]` as each step completes.

1. **Pre-flight** — clean working tree, on `main`, up-to-date with `origin`
2. **Branch** — create `u/jimmyho/claude-code/testflight-build-{N+1}` (approximate)
3. **Build & upload** — `fastlane ios beta` running in background (~10–15 min)
4. **Verify commit** — lane auto-committed `chore(release): set build number to N`
5. **Push** — branch pushed to `origin`
6. **PR** — chore PR opened; record PR number
7. **CI** — `wait_ci.sh` running in background; re-invoked on completion
8. **Merge** — squash-merge; branch cleaned up

## Recipe

### 1. Pre-flight

```bash
git status --porcelain
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **Dirty working tree** (uncommitted or staged changes other than pbxproj): stop. The lane commits only the pbxproj; other uncommitted changes will be left behind and could confuse the reviewer. Ask the user to commit or stash first.
- **Not on `main`**: stop. Confirm the user wants to cut a build from a non-main branch before proceeding.
- **Behind `origin/main`**: pull first:
  ```bash
  git pull --ff-only
  ```

### 2. Create a release branch

Read the current build number from `project.pbxproj`:

```bash
grep CURRENT_PROJECT_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
```

Extract the integer N. Create the branch before anything else — the lane's `git_commit` commits on whatever branch is checked out, so being on the feature branch is mandatory:

```bash
git checkout -b u/jimmyho/claude-code/testflight-build-{N+1}
```

> The branch name uses `N+1` as an approximation. The lane queries ASC for the actual next build number, which may be higher than `N+1` if earlier uploads failed. The PR title is derived from the lane's auto-commit message and will carry the real number regardless.

### 3. Build & upload — `fastlane ios beta`

Run in the background (`run_in_background: true`):

```bash
fastlane ios beta 2>&1 | tee tmp/testflight-build.log
```

The lane (~10–15 min):
- Queries ASC → sets the real next build number
- Bumps `CURRENT_PROJECT_VERSION` in `project.pbxproj`
- Archives and exports the `.ipa` with `-allowProvisioningUpdates`
- Uploads to TestFlight (`skip_waiting_for_build_processing: true`)
- Auto-commits: `chore(release): set build number to <N>`

**Do not use the Monitor tool for ticks — it prompts on each re-arm.** Track progress on 5-minute background sleep ticks instead (memory `feedback_no_prompt_periodic_progress`):

1. Launch `sleep 300` as a background Bash task (`run_in_background: true`).
2. On its completion notification: read the last 10 lines of `tmp/testflight-build.log`, report one-line status, then re-arm with another `sleep 300`.
3. Stop re-arming when the `fastlane ios beta` task exits.

### 4. Verify the auto-commit

After the background task exits:

```bash
git log --oneline -3
tail -60 tmp/testflight-build.log
```

Branch on the result:

**Auto-commit present** (`chore(release): set build number to N`): Record the actual build number N from the commit subject. Proceed to step 5.

**No auto-commit + log shows a build or upload error**: Surface the last 80 lines of `tmp/testflight-build.log` and stop. The branch is clean (nothing committed), so the user can re-run after fixing the issue. Common causes and fixes:
- *Signing failure* — run `fastlane ios verify_auth` to check ASC API key auth; verify the distribution cert and provisioning profile are valid in Xcode / ASC.
- *Archive failure* — the log will show a compiler error; fix the code and re-run from step 3.
- *Upload failure (ASC HTTP 500)* — transient; wait a few minutes and re-run `fastlane ios beta` on the same branch. ASC will increment the build number again.

**No auto-commit + log shows upload success but no commit** (rare — fastlane's `git_commit` failed after a successful upload): the pbxproj is changed but not committed. Stage and commit it manually:

```bash
git add simple-recurring-budgets.xcodeproj/project.pbxproj
```

Read the actual build number from the file:
```bash
grep CURRENT_PROJECT_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
```

Write the commit message to `tmp/commit-msg.txt` with the Write tool:
```
chore(release): set build number to <N>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Then commit:
```bash
git commit -F tmp/commit-msg.txt
```

### 5. Push the branch

```bash
git push -u origin u/jimmyho/claude-code/testflight-build-{N+1}
```

### 6. Open the PR

Write the PR body to `tmp/pr-body.md` with the Write tool:

```
## What
* Bumped build number to <N> and uploaded build <N> to TestFlight.

## Why
New TestFlight build for internal testing.

## Test plan
- [ ] Build <N> appears in TestFlight within ~30 min of Apple processing the upload.

## Tools
- fastlane ios beta

---

## Cross-cutting concerns (PRD §6.8)

N/A — build infrastructure change only; no user-facing code.

- [x] Accessibility — N/A
- [x] Dark Mode — N/A
- [x] Localization — N/A
- [x] Mixpanel — N/A
- [x] UI test screen objects — N/A

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Create the PR:
```bash
gh pr create --title "chore(release): set build number to <N>" --body-file tmp/pr-body.md
```

Record the PR number from the output.

### 7. Wait for CI

Give CI a moment to register the push, then get the run ID:

```bash
sleep 15
gh run list --branch u/jimmyho/claude-code/testflight-build-{N+1} --limit 1 --json databaseId --jq '.[0].databaseId'
```

Wait in the background (`run_in_background: true`):

```bash
bash scripts/wait_ci.sh <run-id> <pr-number>
```

The active CI gates are lint, secrets scan, and the i18n translation gate (the macOS build/test jobs are paused for the June 2026 Actions budget; see AGENTS.md). `wait_ci.sh` polls until the run completes, then prints the step breakdown and PR mergeability. The script times out after ~80 min.

### 8. Squash-merge and clean up

After `wait_ci.sh` exits and all checks passed:

```bash
gh pr merge <pr-number> --squash --delete-branch
git checkout main
git pull --ff-only
git branch -D u/jimmyho/claude-code/testflight-build-{N+1}
git fetch --prune
```

Report success: "Build <N> is in TestFlight (may take ~30 min for Apple to process) and the PR is merged to `main`."

## Commands reference

```bash
git status --porcelain
git branch --show-current
git fetch origin && git log HEAD..origin/main --oneline   # check up to date
grep CURRENT_PROJECT_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
git checkout -b u/jimmyho/claude-code/testflight-build-{N+1}
fastlane ios beta 2>&1 | tee tmp/testflight-build.log     # build + upload + auto-commit
git log --oneline -3                                       # verify auto-commit
git push -u origin u/jimmyho/claude-code/testflight-build-{N+1}
gh pr create --title "chore(release): set build number to <N>" --body-file tmp/pr-body.md
sleep 15
gh run list --branch ... --limit 1 --json databaseId --jq '.[0].databaseId'
bash scripts/wait_ci.sh <run-id> <pr-number>
gh pr merge <pr-number> --squash --delete-branch
git checkout main && git pull --ff-only
git branch -D u/jimmyho/claude-code/testflight-build-{N+1}
git fetch --prune
```
