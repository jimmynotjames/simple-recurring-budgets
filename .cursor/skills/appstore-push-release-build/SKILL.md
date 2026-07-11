---
name: appstore-push-release-build
description: Build and upload the App Store release-candidate build — confirms the release checklist has been worked through, prompts for the new App Store version number, bumps MARKETING_VERSION on a release branch, then runs `fastlane ios beta` so the candidate lands in TestFlight (auto-bumps build number from ASC, archives, uploads, auto-commits the pbxproj bump), then pushes, opens a chore PR, waits for CI, and squash-merges. The same binary is then manually tested via TestFlight and attached to the App Store version in ASC — one build serves both. Does NOT submit for review — that stays a manual App Store Connect step. Use when the release checklist reaches the release-candidate build step, or when asked to push a release build. Invoked via /appstore:push-release-build.
---

# Push the App Store release-candidate build

Produces **the one binary that serves both the final TestFlight test and the
App Store submission**: version bump → branch → build → upload to TestFlight →
commit → PR → CI → merge. TestFlight builds and App Store submissions draw
from the same build pool in ASC, so the exact build the user tests is what
gets attached to the version and submitted — no separate App Store archive.
**Submitting for review remains a manual ASC click.**

Relationship to siblings: this wraps the same `fastlane ios beta` lane as
`appstore-push-testflight-build`, adding the release-checklist confirmation
and the `MARKETING_VERSION` bump. (The dormant `fastlane ios release` lane —
a separate full-binary upload via deliver — is NOT used in this flow.)

The `beta` lane does the heavy lifting: verifies ship secrets
(`scripts/verify_release_secrets.sh`), queries ASC for the next build number,
bumps `CURRENT_PROJECT_VERSION` in `project.pbxproj`, archives and exports the
`.ipa`, uploads to TestFlight, and auto-commits the pbxproj change.

## Preconditions

Normally invoked from `/appstore:prepare-for-release` with the checklist's
Phases 0–3 complete. Either way, **step 1 always asks the user to confirm the
checklist has been worked through** — this skill bakes a binary; it must not
run against unfinished release prep:

- Metadata already pushed and current (`python3
  scripts/translate_metadata/check_metadata.py` exits 0).
- Screenshots already pushed and current (or deliberately unchanged).
- Gate green on `main`.

## Progress checklist

Print this unchecked at the start; re-print with `- [x]` as each step completes.

1. **Prep + version** — user confirmed checklist prep and the new version number
2. **Pre-flight** — clean working tree, on `main`, up-to-date with `origin`
3. **Branch** — create `u/jimmyho/claude-code/release-vX.Y.Z`
4. **Version bump** — `MARKETING_VERSION` set + committed
5. **Build & upload** — `fastlane ios beta` running in background (~10–15 min)
6. **Verify commit** — lane auto-committed `chore(release): set build number to N`
7. **Push** — branch pushed to `origin`
8. **PR** — chore PR opened; record PR number
9. **CI** — `wait_ci.sh` running in background; re-invoked on completion
10. **Merge** — squash-merge; branch cleaned up

## Recipe

### 1. Confirm prep + version number — always prompt, never assume

Read the current value:

```bash
grep MARKETING_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -2
```

Then ask the user (one AskUserQuestion call, three questions):

1. **"Have you worked through the release checklist —
   `/appstore:prepare-for-release`, or manually through
   `docs/app-store-release-checklist.md` Phases 0–3?"** If an in-flight
   snapshot exists in `releases/`, cite its state alongside the question. A
   no (or "not sure") means **stop** and route to
   `/appstore:prepare-for-release` instead of building.
2. **The new App Store version number**, showing the current
   `MARKETING_VERSION` and, if known, the version ASC is expecting. The
   version is a product decision — even if the checklist snapshot already
   names one, confirm it here before it gets baked into a binary.
3. **"Are screenshots and metadata for this release already pushed (or
   deliberately unchanged)?"** A no means stop and finish the checklist's
   Phase 2 first — the binary can upload regardless, but a candidate built
   before the listing is final invites a mismatched submission.

### 2. Pre-flight

```bash
git status --porcelain
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **Dirty working tree**: stop and ask the user to commit or stash first.
  (Exception: an in-flight release-checklist snapshot in `releases/` is fine.)
- **Not on `main`**: stop and confirm before building a release candidate
  from a non-main branch.
- **Behind `origin/main`**: `git pull --ff-only`.

### 3. Create the release branch

```bash
git checkout -b u/jimmyho/claude-code/release-vX.Y.Z
```

### 4. Bump MARKETING_VERSION and commit

Update **every** `MARKETING_VERSION = …;` occurrence in
`simple-recurring-budgets.xcodeproj/project.pbxproj` with the Edit tool
(`replace_all`), then verify:

```bash
grep MARKETING_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj
```

Commit it separately from the lane's build-number auto-commit so history
stays legible. Write the message to `tmp/commit-msg.txt` with the Write tool
(never heredoc):

```
chore(release): bump version to X.Y.Z

Co-Authored-By: <standard Claude co-author footer>
```

```bash
git add simple-recurring-budgets.xcodeproj/project.pbxproj
git commit -F tmp/commit-msg.txt
```

### 5. Build & upload — `fastlane ios beta`

Run in the background (`run_in_background: true`):

```bash
fastlane ios beta 2>&1 | tee tmp/release-build.log
```

The lane (~10–15 min): verifies ship secrets → sets the real next build
number from ASC → archives and exports with `-allowProvisioningUpdates` →
uploads to TestFlight (`skip_waiting_for_build_processing: true`) →
auto-commits `chore(release): set build number to <N>`.

**Do not use the Monitor tool for ticks — it prompts on each re-arm.** Track
progress on 5-minute background sleep ticks instead (memory
`feedback_no_prompt_periodic_progress`): launch `sleep 300` in the background;
on its completion, read the last 10 lines of `tmp/release-build.log`, report a
one-line status, re-arm; stop when the fastlane task exits.

### 6. Verify the auto-commit

```bash
git log --oneline -3
tail -60 tmp/release-build.log
```

**Auto-commit present**: record the build number N. Proceed to step 7.

**Failure branches** (no auto-commit + error in the log): surface the last 80
lines and stop — the version-bump commit stays on the branch, so the lane can
be re-run after the fix.
- *Ship-secrets guard tripped* — configure `config/Secrets.local.xcconfig`
  per `CONTRIBUTING.md § B`, then re-run.
- *Signing failure* — `fastlane ios verify_auth`; check the distribution cert
  and profile in Xcode / ASC.
- *Archive failure* — compiler error in the log; fix and re-run from step 5.
- *Upload failure (ASC HTTP 500)* — transient; wait a few minutes and re-run.

**Upload succeeded but no commit** (rare): stage
`simple-recurring-budgets.xcodeproj/project.pbxproj`, read N from the file,
and commit `chore(release): set build number to <N>` manually via
`tmp/commit-msg.txt`.

### 7–10. Push, PR, CI, merge

Same flow as `appstore-push-testflight-build` steps 5–8:

```bash
git push -u origin u/jimmyho/claude-code/release-vX.Y.Z
gh pr create --title "chore(release): vX.Y.Z — bump version and upload build <N>" --body-file tmp/pr-body.md
sleep 15
gh run list --branch u/jimmyho/claude-code/release-vX.Y.Z --limit 1 --json databaseId --jq '.[0].databaseId'
bash scripts/wait_ci.sh <run-id> <pr-number>   # run_in_background: true
gh pr merge <pr-number> --squash --delete-branch
git checkout main && git pull --ff-only
git branch -D u/jimmyho/claude-code/release-vX.Y.Z
git fetch --prune
```

PR body (via `tmp/pr-body.md`, Write tool): What = version bump to X.Y.Z +
release-candidate build <N> uploaded to TestFlight for App Store submission;
cross-cutting concerns section all N/A (build infrastructure only).

### Done — hand back to the checklist

Report: **"Release candidate build <N> (vX.Y.Z) is uploaded and the PR is
merged. Apple takes ~30 min to process it; then install build <N> via
TestFlight for the final manual test (Settings must show vX.Y.Z (<N>) with no
'Debug' badge). That exact build is what you attach to the version in ASC and
submit for review — nothing has been submitted yet."** If running under
`/appstore:prepare-for-release`, mark the corresponding snapshot items and
continue the checklist.
