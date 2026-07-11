---
name: appstore-prepare-for-release
description: Collaboratively drive an App Store release using docs/app-store-release-checklist.md — creates (or resumes) a per-release snapshot in releases/app-store-release-checklist--vX.Y.Z.md, walks the checklist with the user across sessions, invokes the sibling appstore/translation skills for the heavy steps, and closes out by filling the RELEASES.md entry after the 7-day post-release monitoring window. Use when starting an App Store release, resuming one mid-flight (e.g. "the app got approved", "let's check on the release"), or closing one out. Invoked via /appstore:prepare-for-release.
---

# App Store release (collaborative, snapshot-driven)

Drives a release of Wren to the App Store using the master checklist at
`docs/app-store-release-checklist.md`. A release spans **weeks and multiple
sessions** (submit → review → release → 7-day monitoring), so all state lives
in a per-release snapshot file — never in conversation memory.

**Posture: collaborative, not autonomous.** Many items are `🖱️ MANUAL` (ASC
UI, physical device) — for those, tell the user exactly what to do and wait for
their confirmation. Agent-runnable items you execute directly. `(optional)`
items get a recommendation + a quick user decision, never a silent skip.

## Core rules

- **The snapshot is the single source of truth.** `releases/app-store-release-checklist--vX.Y.Z.md` holds
  every checkbox, date, and decision. Update it *immediately* after each item —
  assume the session could end at any moment.
- **One release in flight at a time.** If two snapshots have
  `Status: in-flight`, stop and ask which is real.
- **Never edit checkbox state from memory of the conversation** — re-read the
  snapshot at the start of every session.
- **Don't renumber checklist IDs.** If the master checklist gained items since
  the snapshot was created (compare against the commit recorded in the snapshot
  header), append the new items to the snapshot in place, marked `(added after
  snapshot)`.
- The heavy steps have dedicated skills — **invoke them, don't reimplement**:
  `/translate-new-strings`, `/audit-translations`, `/appstore:translate-metadata`,
  `/appstore:generate-push-screenshots`, `/translation-accessibility-size-check`,
  `/appstore:push-testflight-build`, `/appstore:push-release-build` (the P4.1
  release-candidate build), and the `app-store-review` skill for compliance
  questions.
- **The App Store version number is always prompted for, never inferred** —
  see step 2 and P0.6.
- Snapshot commits follow repo rules: never on `main` — small chore PRs at
  phase boundaries (see "Persistence" below).

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

Item states: `- [ ]` pending · `- [x]` done · `- [-]` skipped.
After any item that's done/skipped or produced a decision, append an indented
note line:

```markdown
- [x] **P1.3** Audit recency: ...
      > 2026-07-10 — translation-quality audit is 5 weeks old, no string churn
      > since; architecture audit stale but no structural changes. Not re-run.
```

Dates, build numbers, rejection details, and "why we skipped" notes all go in
these note lines — they are what makes the snapshot readable years later.

## Recipe

### 1. Locate state

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
   current value and a suggested bump). It's a product decision — never pick
   it silently, and verify it matches what ASC expects (checklist P0.6).
3. Create `releases/app-store-release-checklist--vX.Y.Z.md`: header per the format above (`Master:` sha from
   `git log -1 --format=%h -- docs/app-store-release-checklist.md`), then the
   verbatim checklist body from Phase 0 onward.
4. Proceed to step 3 starting at P0.1.

### 3. Working loop

1. Re-read the snapshot. Report a one-paragraph status: current phase, first
   unchecked item, elapsed time in any wait state (in review / monitoring day N).
2. For each item in order:
   - **Agent-runnable** (commands, script checks, sibling skills): do it, show
     the result, mark it.
   - **`🖱️ MANUAL`**: give the user the precise steps (deep link into ASC where
     possible), wait for their confirmation, mark it with their answer noted.
   - **`(optional)`**: state a recommendation and why (e.g. "translation audit
     was 2 weeks ago, skip"), let the user decide, mark `[x]` or `[-]` + note.
3. Update the snapshot file after **every** item, not in batches.
4. Batch mechanical items where sensible (e.g. run P2.1 + P2.2 checks together)
   but never mark an item without evidence it passed.

### Executing specific items

**P1.3 — audit & optional-test due-diligence.** Analyze, don't just list dates:

1. `ls docs/audits/` — extract each audit area and its newest date from the
   filenames. Also read the last Run-history entry in
   `scripts/translation-accessibility-size-check/AUDIT_LOG.md`.
2. For each area, measure churn since that date in the paths it covers, e.g.:
   ```bash
   git log --oneline --since=<audit-date> -- <relevant paths> | wc -l
   ```
   (translation quality → `simple-recurring-budgets/**/Localizable.xcstrings`;
   test coverage / UI testing → test targets; architecture / general code →
   app source; localization+VoiceOver → views + xcstrings.)
3. Present a small table — area, last run, churn since, recommendation
   (re-run / skip + one-line reason) — get the user's call per row, and record
   the table + decisions in the snapshot.

**P1.6 — open GitHub issues.** Summarize everything not explicitly deferred:

```bash
gh issue list --state open --json number,title,labels \
  --jq '[.[] | select((.labels | map(.name) | index("deferred")) | not)]'
```

Present each as *fix now / defer (apply the `deferred` label + comment) /
accept as known*; record dispositions in the snapshot. Issues already labeled
`deferred` are skipped (just report the count).

**P4.1 — release-candidate build.** Check for a reusable candidate before
cutting a new one:

```bash
grep MARKETING_VERSION simple-recurring-budgets.xcodeproj/project.pbxproj | head -1
git log --oneline --grep "chore(release): set build number" -1 main
git log <that-sha>..main --oneline -- simple-recurring-budgets/
```

If `MARKETING_VERSION` already equals the new version AND the last command is
empty, the newest TestFlight build is already the release candidate — record
its build number (from the commit subject) and skip to P4.2. Otherwise invoke
`/appstore:push-release-build` and let its recipe run (it re-confirms the
version from P0.6 before baking it into the binary). Either way, copy the
build number into the snapshot header — this one build is both the final
TestFlight test target (P4.3) and the binary attached in P5.1.

**P4.3 — final manual test.** 🖱️ — give the user the exact build number to
install via TestFlight and what to verify: the Settings version row shows
**vX.Y.Z (N)** and **no "Debug" badge** (Debug badge = local dev build, not
the candidate), then onboarding, core flows, and this release's new features.
Wait for their result and record the tested build number.

### 4. Wait states — end the session cleanly

Two points intentionally span days; do not try to poll or babysit them:

- **After P5.3 (submitted)**: tell the user — "Re-invoke `/appstore:prepare-for-release`
  when Apple emails a status change (approved/rejected), or to check anything
  meanwhile." Persist the snapshot first.
- **During Phase 7 (monitoring)**: on each invocation compute the monitoring
  day from the `Released:` date, run the day-appropriate checks (Mixpanel via
  MCP for P7.1/P7.3/P7.4 event + funnel checks; the user reports crashes from
  Xcode Organizer and ratings from ASC), note results, and say when to come
  back next.

### 5. Persistence (chore PRs)

Snapshot edits are docs-only. At each **phase boundary** (and always after
P5.3 and P7.5), commit the snapshot to a branch and PR it:

```bash
git checkout -b u/jimmyho/claude-code/release-vX.Y.Z-checklist-p<N>
git add releases/ RELEASES.md docs/app-store-release-checklist.md
# commit message via tmp/commit-msg.txt (never heredoc), e.g.:
#   chore(release): vX.Y.Z checklist through Phase <N> [skip ci]
git commit -F tmp/commit-msg.txt
git push -u origin <branch> && gh pr create ... && merge when green
```

Between boundaries, uncommitted snapshot edits in the working tree are fine —
but if the user needs a clean tree, commit the snapshot first rather than
stashing it.

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
line explaining why, and PR the snapshot anyway — a dead-end record is still
context for the next attempt.
