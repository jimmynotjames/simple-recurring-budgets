---
name: appstore-prepare-for-release
description: Collaboratively drive an App Store release using docs/app-store-release-checklist.md — creates (or resumes) a per-release snapshot in releases/app-store-release-checklist--vX.Y.Z.md, walks the checklist with the user across sessions, invokes the sibling appstore/translation skills for the heavy steps, and closes out by filling the RELEASES.md entry after the ~1-week post-release monitoring window. Use when starting an App Store release, resuming one mid-flight (e.g. "the app got approved", "let's check on the release"), or closing one out. Invoked via /appstore:prepare-for-release.
---

# App Store release (collaborative, snapshot-driven)

Drives a release of Wren to the App Store using the master checklist at
`docs/app-store-release-checklist.md`. A release spans weeks and multiple
sessions (submit → review → release → ~1 week of monitoring), so all state lives
in a per-release snapshot file, never in conversation memory.

Posture: collaborative, not autonomous. For `🎈 MANUAL` items (ASC UI, physical
device), tell the user exactly what to do and wait for confirmation. Run
agent-runnable items directly. For `🤔 (optional)` items, give a recommendation
and get a quick user decision; never skip silently.

## Model preference

- Run this skill on the latest Sonnet-tier model (or its contemporary
  equivalent). The orchestration (checklist walking, snapshot edits, invoking
  sibling skills) is model-light; translation, audits, and screenshot content
  are already delegated to Opus-tier subagents by those skills.
- At the start of each session, check the model and the effort level.
  Model: if the session is not on the latest Sonnet-tier model or equivalent
  (a smaller model is risky on the judgment items P0.6, P1.6–P1.8, P6.1; a
  premium top-tier model is wasteful for checklist mechanics), tell the user and
  confirm before proceeding. Effort: if the effort setting is knowable and isn't
  the default `high` (or its era's equivalent), flag it in the same
  confirmation; if not knowable, ask the user to confirm once at the first
  session of a release (record the answer in the snapshot's P0.7 Note; don't
  re-ask every session). Never silently continue on a mismatched model.
- Effort `high` (default) is right. Don't drop to low/medium: the judgment items
  (P0.6, P1.6–P1.8, P6.1) deserve full reasoning depth and the token savings are
  trivial at release cadence. Don't raise to xhigh/max: that tier is for
  long-horizon coding/agentic work, not human-paced checklist driving.
- Judgment-heavy items escalate to the latest Opus-tier model (or equivalent).
  For the analysis behind P1.6 (open-issue triage), P1.7 (dependency-bump
  calls), P1.8 (Swift/deployment-target tradeoffs), and P6.1 (interpreting a
  rejection), spawn a subagent on that model (Agent tool, `model: "opus"` or the
  current equivalent) to analyze and return a recommendation. The Sonnet-tier
  driver relays it and the decision still goes to the user; the items'
  prompts-and-dispositions rules are unchanged. Don't escalate the mechanical
  parts (running `gh issue list`, reading `Package.resolved`), only the judgment.

## Core rules

- The snapshot is the single source of truth. `releases/app-store-release-checklist--vX.Y.Z.md` holds
  every checkbox, date, and decision. Update it immediately after each item;
  the session could end at any moment.
- One release in flight at a time. If two snapshots have
  `Status: in-flight`, stop and ask which is real.
- Never edit checkbox state from memory of the conversation; re-read the
  snapshot at the start of every session.
- Don't renumber checklist IDs. If the master checklist gained items since
  the snapshot was created (compare against the commit recorded in the snapshot
  header), append the new items to the snapshot in place, marked `(added after
  snapshot)`.
- The heavy steps have dedicated skills; invoke them, don't reimplement:
  `/translate-new-strings`, `/audit-translations`, `/appstore:translate-metadata`,
  `/appstore:generate-push-screenshots`, `/translation-accessibility-size-check`,
  `/appstore:push-testflight-build`, `/appstore:push-release-build` (the P4.1
  release-candidate build), and the `app-store-review` skill for compliance
  questions.
- Always prompt for the App Store version number, never infer it (step 2, P0.6).
- Snapshot commits never go on `main`: small chore PRs at phase boundaries (see "Persistence").

## Snapshot format

`releases/app-store-release-checklist--vX.Y.Z.md`:

```markdown
# Release vX.Y.Z — checklist snapshot

Master: docs/app-store-release-checklist.md @ <short-sha at snapshot creation>
Status: in-flight            # in-flight | complete | abandoned
Version: X.Y.Z · Build: —    # build filled at P4.1
Started: YYYY-MM-DD · Submitted: — · Released: — · Monitoring ends: —

<full copied checklist body, Phase 0 → Phase 7>
```

Checkboxes are binary: `- [ ]` not handled yet · `- [x]` handled (done or
deliberately skipped; the Note says which). Every template item carries a
`> Note:` field; fill it in when you mark the item:

```markdown
- [x] **P1.3** 🎈 Review recent audits: ...
      > Note: 2026-07-10 — Jimmy reviewed the audit list; translation-quality
      > audit is recent enough and nothing else warranted a re-run. Skipped.
```

Dates, build numbers, rejection details, and "Skipped — reason" / "N/A" calls
go in the Note. Never check a box and leave its Note empty.

## Recipe

### 1. Locate state

Sync with `origin/main` first, so the snapshot and checklist you read are
current (snapshot chore PRs land on `main`):

```bash
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **On `main`, behind `origin/main`**: `git pull --ff-only`. Uncommitted edits
  are fine; git refuses if an incoming commit touches a file you've modified. If
  it refuses or can't fast-forward, stop and ask the user.
- **On a step-5 chore branch whose PR has merged** (`gh pr view --json state`
  says `MERGED`): `git switch main && git pull
  --ff-only`.
- **On another branch**: don't switch or merge. If it's behind `origin/main`,
  say by how many commits and confirm before continuing.

Sibling skills invoked later in this session skip their own sync step; this one
covers them.

Then find the in-flight snapshot:

```bash
ls releases/ 2>/dev/null
grep -l "Status: in-flight" releases/*.md 2>/dev/null
```

- **In-flight snapshot found** → resume (step 3).
- **No `releases/` dir or no in-flight snapshot** → start a new release (step 2).

### 2. Start a new release

1. Read `docs/app-store-release-checklist.md` fully, plus the newest
   `RELEASES.md` entry.
2. Determine the version: read `MARKETING_VERSION` from
   `simple-recurring-budgets.xcodeproj/project.pbxproj`, then **prompt the
   user for the new App Store version number** (AskUserQuestion, showing the
   current value and a suggested bump). It's a product decision; never pick
   it silently, and verify it matches what ASC expects (checklist P0.6).
3. Create `releases/app-store-release-checklist--vX.Y.Z.md`: header per the format above (`Master:` sha from
   `git log -1 --format=%h -- docs/app-store-release-checklist.md`), then the
   verbatim checklist body from Phase 0 onward.
4. Proceed to step 3 starting at P0.1.

### 3. Working loop

1. Re-read the snapshot. Report a one-paragraph status: current phase, first
   unchecked item, elapsed time in any wait state (in review / days since
   release).
2. For each item in order:
   - Agent-runnable (commands, script checks, sibling skills): do it, show
     the result, mark it and fill its Note.
   - `🎈 MANUAL`: give the user the precise steps (deep link into ASC where
     possible), wait for their confirmation, mark it with their answer in the
     Note.
   - `🤔 (optional)`: state a recommendation and why (e.g. "translation
     audit was 2 weeks ago, skip"), let the user decide, mark `[x]` with the
     decision in the Note (e.g. `Skipped — audit 2 weeks old, no churn`).
   - Every prompt to the user (`AskUserQuestion` or plain text) must name the
     item ID and what it checks: put the ID in the question `header` chip (e.g.
     `header: "P1.6 issue"`, not just `"Issue #304"`) and open the question text
     with the ID, quoting the item's checklist wording verbatim if short or
     summarizing it in 1-2 sentences if long. Never prompt with only surrounding
     context (e.g. an issue title) and no ID.
3. Update the snapshot file after every item, not in batches.
4. Batch mechanical items where sensible (e.g. run P2.1 + P2.2 checks together)
   but never mark an item without evidence it passed.

### Executing specific items

**P0.4 — auth sanity.** Two independent credentials; check both, don't let one stand in for the other:
1. **ASC API key** (REST auth fastlane uses for `deliver`/`pilot`/etc.): run
   `fastlane ios verify_auth`. A pass only proves the API key works; it says nothing about the cert below.
2. **Apple Distribution certificate** (code-signing identity used to archive/
   sign the build): always a 🎈 MANUAL pause. Never infer it from
   `verify_auth` passing, and don't script a probe for it (no efficient
   programmatic check). Ask the user to confirm it exists and isn't expired,
   and wait for their answer:
   - Xcode → Settings → Accounts → Apple ID → **Manage Certificates...** →
     find **Apple Distribution** (Xcode flags it if expired/expiring; absent if it doesn't exist yet).
   - Or: App Store Connect → **Certificates, Identifiers & Profiles →
     Certificates** → Apple Distribution cert → expiry date on its detail page.
   If it doesn't exist, the user creates it there (Xcode can also generate one
   via automatic signing); record in the Note that it had to be created.
If `verify_auth` fails, follow API-key recovery in `fastlane/SETUP.md` (separate from cert recovery).

**P1.3 — audit review.** 🎈 The user reviews and decides. Present a short list: `ls docs/audits/` (dates are in the filenames) plus the last
Run-history entry in
`scripts/translation-accessibility-size-check/AUDIT_LOG.md`. The user decides whether anything is due for another
round. Record their decision in the Note.

**P1.6 — open GitHub issues.** 🎈 The user dispositions every issue; you
summarize. Fetch everything not deferred:

```bash
gh issue list --state open --json number,title,labels \
  --jq '[.[] | select((.labels | map(.name) | index("deferred")) | not)]'
```

Summarize each issue, then prompt for a decision per
issue (AskUserQuestion): *fix now / defer (apply the `deferred` label +
comment) / accept as known*. Never disposition an issue yourself. Record the
disposition list in the Note. Skip issues already labeled `deferred` (report the count).

**P2.3 — translation-quality audit.** 🤔 Before recommending, tell the user up
front (in the prompt itself, not a footnote) that `/audit-translations` is intensive: it fans
out an Opus subagent per locale (49 locales) and burns significant tokens/time. Then recommend based on
how many strings were added since the newest `translation-quality-audit-*` in
`docs/audits/` (per the item's own criterion), and let the user decide.

**P3.7 — CloudKit Production schema.** Don't drive this inline; invoke the
`cloudkit-deploy-schema` skill, which owns the full recipe (preflight checks,
greenfield-vs-incremental handling, stale-field triage, and the mandatory
confirmation gates before anything destructive/production-affecting). Run it
on Opus-tier, not the orchestrating model (spawn an Opus subagent if the session is on Sonnet):
Production schema mutations are practically permanent (fields can't be deleted
once deployed), the same high-consequence profile as P1.6/P1.7/P1.8/P6.1.
Record in the Note only a summary of what `cloudkit-deploy-schema`
did (method, fields, verification).

**P4.1 — release-candidate build.** Check for a reusable candidate first:

```bash
grep MARKETING_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
git log --oneline --grep "chore(release): set build number" -1 main
git log <that-sha>..main --oneline -- simple-recurring-budgets/
```

If `MARKETING_VERSION` already equals the new version AND the last command is
empty, the newest TestFlight build is already the release candidate: record
its build number (from the commit subject) and skip to P4.2. Otherwise invoke
`/appstore:push-release-build` and let its recipe run (it re-confirms the
version from P0.6). Either way, copy the
build number into the snapshot header; this one build is both the final
TestFlight test target (P4.3) and the binary attached in P5.1.

**P4.3 — final manual test.** 🎈 Give the user the exact build number to
install via TestFlight. Default to updating over their existing install, not
deleting first (deleting destroys local data not yet synced to CloudKit; the
fresh-install check is P4.5's Device B). Verify: the Settings version row shows
**vX.Y.Z (N)** and no "Debug" badge (a Debug badge means a local dev build, not
the candidate), then create a budget, log spending, and exercise this release's
new features. Don't ask for an "iCloud sync round-trip" here (a single device
can't confirm data reached CloudKit; that's P4.5). Wait for the result and
record the tested build number.

**P4.5 — two-device iCloud sync verification (also the fresh-install
check).** 🎈 Give the user the checklist item's exact steps verbatim (it's
self-contained). Device A is already updated (P4.3); Device B is deleted and
fresh-installed, signed into the same iCloud account, and should
populate from Device A's data; then a change on either device should
propagate to the other. This is the real verification of P3.7's Production
schema deploy (a single device can't rule out a false positive from local
caching), and Device B never needs to be the user's primary device, so nothing at risk gets deleted.
A sync failure here is a hard blocker on P5.1: send the user back to
`/cloudkit-deploy-schema` rather than letting them proceed to submission.
Record pass/fail and which direction(s) were tested.

### 4. Wait states — end the session cleanly

Two points intentionally span days; don't poll or babysit them:

- **After P5.3 (submitted)**: tell the user "Re-invoke `/appstore:prepare-for-release`
  when Apple emails a status change (approved/rejected), or to check anything
  meanwhile." Persist the snapshot first.
- **During Phase 7 (monitoring)**: on each invocation report how long the
  release has been out (from the `Released:` date), run whichever Phase 7
  checks are still open (Mixpanel via MCP for the P7.1/P7.4 event + funnel
  checks; the user reports crashes from Xcode Organizer and ratings from ASC),
  record results in each item's Note, and say when to come back next. The
  window is ~1 week — P7.4 closes it with an explicit verdict.

### 5. Persistence (chore PRs)

Snapshot edits are docs-only. At each phase boundary (and always after
P5.3 and P7.5), commit the snapshot to a branch and PR it:

```bash
git checkout -b u/jimmyho/claude-code/release-vX.Y.Z-checklist-p<N>
git add releases/ RELEASES.md docs/app-store-release-checklist.md
# commit message via tmp/commit-msg.txt (never heredoc), e.g.:
#   chore(release): vX.Y.Z checklist through Phase <N> [skip ci]
git commit -F tmp/commit-msg.txt
git push -u origin <branch> && gh pr create ... && merge when green
```

Between boundaries, uncommitted snapshot edits in the working tree are fine;
if the user needs a clean tree, commit the snapshot rather than stashing it.

### 6. Close-out (P7.5–P7.6)

1. Fill in the `RELEASES.md` entry: submitted/build/version line, features
   shipped (cross-reference `F-x.xx` IDs from
   `docs/product-features-planning.md`), and the cross-cutting confirmations
   recorded at P3.5.
2. Set the snapshot header to `Status: complete`.
3. Ask the user for checklist retro items (P7.6); apply edits to
   `docs/app-store-release-checklist.md`.
4. One final chore PR with all three files. Report: version, build, submitted →
   released dates, monitoring verdict, and any checklist changes made.

## Abandoning a release

If the user cancels a release mid-flight, set `Status: abandoned` with a note
line explaining why, and PR the snapshot anyway (a dead-end record is context for the next attempt).
