---
name: create-pr
description: Turn already-written code changes into a reviewed, gated, open PR. Spawns a fresh-context code-reviewer subagent for a correctness-first look at the diff, audits the AGENTS.md cross-cutting concerns checklist (accessibility, localization, translations, Mixpanel, UI test screen objects), fills in any gaps autonomously, runs `make gate`, commits residual fixes, pushes the branch, and opens the PR. Use when the solution is mostly done and you want to review, gate, and ship it to a PR — without involving a GitHub issue. Does NOT merge; pair with /merge-pr after review. Invoked via /create-pr.
---

# Create a PR

Turns already-written code changes into a **reviewed, gated, open PR**. The implementation is expected to be substantially complete; this skill closes the remaining gaps (cross-cutting concerns, review findings, gate) and gets the PR open cleanly.

**Does not merge.** The PR stays open for human review. Use `/merge-pr <PR>` after you're satisfied.

## Progress checklist

Print this unchecked at the start; tick each step as it completes.

1. **Branch** — confirm on a feature branch (create one if on `main`)
2. **Initial commit** — uncommitted changes staged and committed so the diff is reviewable
3. **Fresh-eye review** — subagent reads the full diff; findings processed
4. **Cross-cutting concerns** — AGENTS.md §6.8 checklist audited against the diff
5. **Gaps fixed** — review findings and any cross-cutting gaps addressed
6. **Gate** — `make gate` passes clean
7. **Commit fixes** — any post-review changes committed
8. **Push** — branch pushed to `origin`
9. **PR** — PR opened with `tmp/pr-body.md`; URL reported

## Recipe

### 1. Establish branch state

```bash
git status --short
git branch --show-current
git log --oneline main..HEAD
```

**On `main` with uncommitted changes**: create a feature branch *now*, before the first `git add` (AGENTS.md: "Create the branch before the first `git add`"):
```bash
git checkout -b u/jimmyho/claude-code/<short-kebab-description>
```
Branch name format: `u/jimmyho/claude-code/<short-kebab-description>`, all lowercase, no underscores.

**On `main` with commits already on main**: this path requires a force-push to move commits to a branch — stop and ask the user how to proceed.

**On a feature branch with no commits and no uncommitted changes**: nothing to PR. Ask for clarification.

**On a feature branch with at least one commit or uncommitted changes**: proceed.

### 2. Commit any uncommitted changes

If `git status --short` shows uncommitted changes, stage and commit them now so the reviewer has a clean diff to read.

Stage changes for the PR (use specific file paths, not `git add -A`):
```bash
git status --short   # identify the changed files
git add <specific-files>
```

Write the commit message to `tmp/commit-msg.txt` using the **Write tool** (never inline heredoc — memory `feedback_commit_message_file`), following the commit subject/body conventions in AGENTS.md §"Commit and PR style". Then commit:

```bash
git commit -F tmp/commit-msg.txt
```

### 3. Fresh-eye code review

Get the full branch diff:
```bash
git diff main..HEAD
```

Spawn a **`general-purpose` Agent** with the diff in the prompt — a fresh context so it has no prior conversation history coloring the review. Brief it as:

> "You are reviewing a code diff for a Swift 6 / SwiftUI / SwiftData / CloudKit iOS 26 app. Review for: correctness bugs, data-race or actor-isolation issues, SwiftData model integrity (Sendable, @ModelActor, PersistentIdentifier usage), architectural problems, and serious extensibility risks. Do NOT flag style issues — a linter handles those. For each finding: state the file and approximate line, describe the issue, rate it high/medium/low. Append the full diff below."
>
> [paste the full `git diff main..HEAD` output]

Process the returned findings:
- **High** — fix now, autonomously. Only pause for user input when a finding is genuinely ambiguous about product intent (i.e., you cannot determine the right behavior from the surrounding code and PRD).
- **Medium** — fix real bugs and architectural issues; skip subjective preferences or refactoring suggestions outside the change's scope.
- **Low** — skip (style, premature optimization; not your job here).

Apply all fixes at once with the Edit or Write tool. Do not re-spawn the reviewer after each fix.

### 4. Cross-cutting concerns (AGENTS.md §6.8)

For each concern, read the diff to determine whether it applies. This is a code-reading check — no user input needed unless something is genuinely ambiguous.

**Accessibility**
Applies if: the diff adds or modifies a SwiftUI `View`.
Check: every new composite view has `.accessibilityLabel`/`.accessibilityHint` on interactive or decorative elements; no fixed heights that clip text; destructive controls have `.accessibilityAction(named:)`.

**Localized source strings**
Applies if: the diff adds any `Text("…")` literal or string that appears in the UI.
Check: strings use `String(localized:)` or `Text(LocalizedStringResource(…))` with a `comment:`; no hard-coded English in production Views. Locale-invariant values (version numbers, ISO codes) use `Text(verbatim:)`.

**Translations**
Applies if: any localized key was added or changed.
Check:
```bash
python3 scripts/check_translations.py
```
If exit non-zero: invoke the `translate-new-strings` skill autonomously to bring all 49 locales current before proceeding. The pre-push hook will block the push otherwise.

**Mixpanel events**
Applies if: the diff introduces a new user-initiated action that materially changes app state (new CTA, new destructive action, new toggle affecting usage or retention).
Check: an `AnalyticsClient.track(…)` call is present per `docs/analytics-spec.md`. No PII.

**UI test screen objects**
Applies if: the diff changes navigation structure, button labels, toolbar items, or sheet routes in any view covered by `simple-recurring-budgetsUITests/`.
Check: the relevant screen object (`BudgetsScreen.swift`, `BudgetDetailScreen.swift`, `AddBudgetScreen.swift`, `AddExpenseScreen.swift`, `SettingsScreen.swift`) is updated in the same change. Note in the PR body that `make test-ui` should be run before merge.

Fix any gaps you find. For translations, run `translate-new-strings` as a full sub-task (it is autonomous).

### 5. Run the gate

```bash
make gate
```

Run in the background (`run_in_background: true`) — `make gate` runs `make format && make lint-fix && make build && make test` and tees output to `tmp/gate.log`. **Do not open the PR until the gate is green.**

If the gate fails: read `tmp/gate.log`, fix the failure, and re-run `make gate`. Format and lint-fix output is auto-applied; build and test failures require code changes.

### 6. Commit any post-review changes

If steps 3–5 produced uncommitted edits:

```bash
git diff --stat HEAD
git add <specific-files>
```

Write a commit message to `tmp/commit-msg.txt` (e.g. `Applied pre-PR review fixes.`) and commit:
```bash
git commit -F tmp/commit-msg.txt
```

If there are no new changes after the gate (format/lint applied cleanly to already-committed code), skip this step.

### 7. Push the branch

```bash
git push -u origin <branch-name>
```

### 8. Open the PR

Write the PR body to `tmp/pr-body.md` using the **Write tool**, following the structure in `.github/pull_request_template.md` (What / Why / Test plan / Tools, then the cross-cutting-concerns checklist marked done-or-N/A from step 4). End with the `Co-Authored-By:` footer.

Guidelines (per AGENTS.md §"Commit and PR style"):
- **No `Closes #N`** unless there is a directly related issue — use `Refs #N` for related issues, omit entirely if none.
- PR title follows the subject convention: past-tense verb, sentence case, ≤72 chars, no `feat:`/`fix:`/`chore:` prefix. Examples: `"Fixed carry-over spillover to honor lastResetDate"`, `"Added biweekly start-date anchoring to Add Budget screen"`.

Create the PR:
```bash
gh pr create --title "<Past-tense subject>" --body-file tmp/pr-body.md
```

Report the PR URL to the user.

## Autonomy

Run all steps without prompting, except when a review finding is genuinely ambiguous about product intent. Gate commands, git operations, and `gh pr create` are all allowlisted. Translation pipeline runs (if triggered) are autonomous per memory `feedback_localization_autonomous`.

## What this skill does NOT do

- **Does not merge.** Use `/merge-pr <PR>` after you're satisfied with the review.
- **Does not run `make test-ui`** (slow, opt-in via CI comment `/test-full`). Note explicitly in the PR body if screen objects were updated and a UI test pass is needed.
- **Does not handle OpenSpec changes.** If the change needs spec/doc updates, the OpenSpec workflow (`/opsx:verify` → `/opsx:archive`) runs separately after merge.
- **Does not involve a GitHub issue.** For issue-linked work, use `/create-pr-for-issue <N>` instead.
