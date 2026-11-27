---
name: appstore-push-testflight-build
description: Build and ship a TestFlight build end-to-end — creates a release branch, runs `fastlane ios beta` (auto-bumps build number from ASC, archives, uploads, auto-commits the pbxproj bump), then hands the commit to `/create-pr` (gate, push, PR) and stops; `/merge-pr` lands it on a later turn. Use when cutting a new TestFlight build. Invoked via /appstore-push-testflight-build.
---

# Push a TestFlight build

Full TestFlight release cut: branch → build → upload → commit, then `/create-pr`. Merging is `/merge-pr` on a later turn.

The `fastlane ios beta` lane queries App Store Connect for the next build number, bumps `CURRENT_PROJECT_VERSION` in `project.pbxproj`, archives and exports the `.ipa`, uploads it to TestFlight (without waiting for Apple to process it), and auto-commits the pbxproj change. This skill adds branch discipline, then routes the commit through the same PR path as every other change (AGENTS.md § "Where each check runs").

## Progress checklist

Print this unchecked at the start; re-print with `- [x]` as each step completes.

1. **Pre-flight** — clean working tree, on `main`, up-to-date with `origin`
2. **Branch** — create `u/jimmyho/claude-code/testflight-build-{N+1}` (approximate)
3. **Build & upload** — `fastlane ios beta` running in background (~10–15 min)
4. **Verify commit** — lane auto-committed `chore(release): set build number to N`
5. **PR** — `/create-pr` run (gate, push, PR opened); record PR number
6. **Hand back** — report the PR; `/merge-pr <PR>` on a later turn

## Recipe

### 1. Pre-flight

```bash
git status --porcelain
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **Dirty working tree** (uncommitted or staged changes other than pbxproj): stop. The lane commits only the pbxproj, so other changes would be left behind. Ask the user to commit or stash first.
- **Not on `main`**: stop and confirm the user wants a build from a non-main branch.
- **Behind `origin/main`**: pull first:
  ```bash
  git pull --ff-only
  ```

### 2. Create a release branch

Read the current build number from `project.pbxproj`:

```bash
grep CURRENT_PROJECT_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
```

Extract the integer N. Create the branch first: the lane's `git_commit` commits on whatever branch is checked out.

```bash
git checkout -b u/jimmyho/claude-code/testflight-build-{N+1}
```

> `N+1` in the branch name is approximate: the lane queries ASC for the real next number, which may be higher if earlier uploads failed. The PR title uses the real number from the lane's auto-commit message.

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

Do not use the Monitor tool for ticks (it prompts on each re-arm). Track progress on 5-minute background sleep ticks (memory `feedback_no_prompt_periodic_progress`):

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

**Auto-commit present** (`chore(release): set build number to N`): record N from the commit subject; go to step 5.

**No auto-commit + build or upload error in the log**: surface the last 80 lines of `tmp/testflight-build.log` and stop. The branch is clean, so the user can re-run after fixing. Common causes:
- *Signing failure* — run `fastlane ios verify_auth` to check ASC API key auth; verify the distribution cert and provisioning profile are valid in Xcode / ASC.
- *Archive failure* — compiler error in the log; fix and re-run from step 3.
- *Upload failure (ASC HTTP 500)* — transient; wait a few minutes and re-run `fastlane ios beta` on the same branch. ASC will increment the build number again.

**Upload succeeded but no commit** (rare: `git_commit` failed after upload): the pbxproj is changed but uncommitted. Stage and commit it manually:

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

### 5. Open the PR — `/create-pr`

Invoke the `create-pr` skill on this branch. It runs the gate (no simulator), pushes, and opens the PR. For this chore PR:

- **Title:** `chore(release): set build number to <N>`
- **Body** (`tmp/pr-body.md`): What = "Bumped build number to <N> and uploaded build <N> to TestFlight."; Why = "New TestFlight build for internal testing."; Test plan = "Build <N> appears in TestFlight within ~30 min of Apple processing the upload."; Tools = `fastlane ios beta`; every cross-cutting concern N/A (build infrastructure only).

Record the PR number.

### 6. Hand back

Stop here: never merge on the turn the PR is opened (AGENTS.md § "Commit and PR style"). Report: "Build <N> is in TestFlight (may take ~30 min for Apple to process). PR #<PR> is open; CI runs the full suite on it. Merge it with `/merge-pr <PR>` once it's green."

## Commands reference

```bash
git status --porcelain
git branch --show-current
git fetch origin && git log HEAD..origin/main --oneline   # check up to date
grep CURRENT_PROJECT_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
git checkout -b u/jimmyho/claude-code/testflight-build-{N+1}
fastlane ios beta 2>&1 | tee tmp/testflight-build.log     # build + upload + auto-commit
git log --oneline -3                                       # verify auto-commit
# then /create-pr; /merge-pr <PR> on a later turn
```
