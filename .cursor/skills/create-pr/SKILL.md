---
name: create-pr
description: Turn already-written code changes into a reviewed, gated, open PR. Spawns a fresh-context code-reviewer subagent for a correctness-first look at the diff, audits the AGENTS.md cross-cutting concerns checklist (accessibility, localization, translations, Mixpanel, UI test screen objects), fills in any gaps autonomously, runs `make gate`, commits residual fixes, pushes the branch, and opens the PR. Use when the solution is mostly done and you want to review, gate, and ship it to a PR — without involving a GitHub issue. Does NOT merge; pair with /merge-pr after review. Invoked via /create-pr.
---

# Create a PR

Turns substantially complete code changes into a reviewed, gated, open PR. This skill closes the remaining gaps (cross-cutting concerns, review findings, gate) and opens the PR.

Does not merge. Use `/merge-pr <PR>` after review.

## Progress checklist

Print this unchecked at the start; tick each step as it completes.

1. **Branch** — on a feature branch (create one if on `main`)
2. **Initial commit** — uncommitted changes committed so the diff is reviewable
3. **Fresh-eye review** — full diff reviewed; findings processed
4. **Cross-cutting concerns** — AGENTS.md §6.8 checklist audited against the diff
5. **Gaps fixed** — review findings and cross-cutting gaps addressed
6. **Gate** — `make gate` passes clean *(or skipped after docs-only CI confirmation)*
7. **Commit fixes** — post-review changes committed
8. **Push** — branch pushed to `origin`
9. **PR** — PR opened with `tmp/pr-body.md`; URL reported

## Recipe

### 1. Establish branch state

```bash
git status --short
git branch --show-current
git log --oneline main..HEAD
```

- **On `main` with uncommitted changes:** create a feature branch before the first `git add` (AGENTS.md: "Create the branch before the first `git add`"):
  ```bash
  git checkout -b u/jimmyho/<tool>/<short-kebab-description>
  ```
  Branch name format: `u/jimmyho/<tool>/<short-kebab-description>`, all lowercase, no underscores. `<tool>` documents authorship (e.g. `cursor`, `claude-code`, `cursor+claude`).
- **On `main` with commits already on main:** moving them to a branch needs a force-push. Stop and ask the user how to proceed.
- **On a feature branch with no commits and no uncommitted changes:** nothing to PR. Ask for clarification.
- **On a feature branch with commits or uncommitted changes:** proceed.

### 2. Commit uncommitted changes

If `git status --short` shows uncommitted changes, commit them so the reviewer has a clean diff.

Stage specific file paths, not `git add -A`:
```bash
git status --short   # identify the changed files
git add <specific-files>
```

Write the commit message to `tmp/commit-msg.txt` with the Write tool (never an inline heredoc; memory `feedback_commit_message_file`), following the subject/body conventions in AGENTS.md §"Commit and PR style". Then:

```bash
git commit -F tmp/commit-msg.txt
```

### 3. Fresh-eye code review

Get the full branch diff:
```bash
git diff main..HEAD
```

Spawn a `general-purpose` Agent with the diff in the prompt (fresh context, so no prior conversation colors the review). Brief it as:

> "You are reviewing a code diff for a Swift 6 / SwiftUI / SwiftData / CloudKit iOS 26 app. Review for: correctness bugs, data-race or actor-isolation issues, SwiftData model integrity (Sendable, @ModelActor, PersistentIdentifier usage), architectural problems, and serious extensibility risks. Do NOT flag style issues — a linter handles those. For each finding: state the file and approximate line, describe the issue, rate it high/medium/low. Append the full diff below."
>
> [paste the full `git diff main..HEAD` output]

Process the findings:
- **High:** fix now, autonomously. Pause only when a finding is genuinely ambiguous about product intent (you can't determine the right behavior from the surrounding code and PRD).
- **Medium:** fix real bugs and architectural issues; skip subjective preferences and refactors outside the change's scope.
- **Low:** skip (style, premature optimization).

Apply all fixes at once with Edit or Write. Don't re-spawn the reviewer after each fix.

**Cross-tool execution.** Claude Code: spawn the `general-purpose` subagent as above. Cursor: no subagent fan-out; do the review inline in the same session against the same criteria.

### 4. Cross-cutting concerns (AGENTS.md §6.8)

For each concern, read the diff to decide whether it applies. This is a code-reading check; ask the user only if something is genuinely ambiguous.

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
If exit non-zero: invoke the `translate-new-strings` skill autonomously to bring all 49 locales current. The pre-push hook blocks the push otherwise.

**Mixpanel events**
Applies if: the diff introduces a new user-initiated action that materially changes app state (new CTA, new destructive action, new toggle affecting usage or retention).
Check: an `AnalyticsClient.track(…)` call is present per `docs/analytics-spec.md`. No PII.

**UI test screen objects**
Applies if: the diff changes navigation structure, button labels, toolbar items, or sheet routes in any view covered by `simple-recurring-budgetsUITests/`.
Check: the relevant screen object (`BudgetsScreen.swift`, `BudgetDetailScreen.swift`, `AddBudgetScreen.swift`, `AddExpenseScreen.swift`, `SettingsScreen.swift`) is updated in the same change. Note in the PR body that `make test-ui` should be run before merge.

Fix any gaps. For translations, run `translate-new-strings` as a full autonomous sub-task.

### 5. Docs-only? Confirm CI skip (heuristic)

Before the gate, run `git diff main..HEAD --name-only`. If every changed path looks documentation-only (e.g. `docs/**`, `*.md`, `openspec/**`, `.cursor/**`, `.claude/**`, `.github/**/*.md`), stop and ask the user:

> This looks like a documentation-only change. Add `[skip ci]` to the commit message before push to skip GitHub Actions? (Heuristic — not 100% reliable.)

- **Yes:** ensure the HEAD commit includes `[skip ci]` (amend or a small follow-up commit before push). You may skip the local gate (step 6); there is no app code to validate.
- **No:** proceed with the gate and a normal commit message.

Never skip silently; user confirmation is required. False positives and negatives are acceptable.

### 6. Run the gate

```bash
make gate
```

Run in the background (`run_in_background: true`). `make gate` runs `make format && make lint-fix && make build && make test` and tees output to `tmp/gate.log`. Don't open the PR until the gate is green (unless step 5 confirmed a docs-only skip).

On failure: read `tmp/gate.log`, fix, and re-run. Format and lint-fix output is auto-applied; build and test failures need code changes.

### 7. Commit post-review changes

If steps 3–6 left uncommitted edits:

```bash
git diff --stat HEAD
git add <specific-files>
```

Write a commit message to `tmp/commit-msg.txt` (e.g. `Applied pre-PR review fixes.`) and commit:
```bash
git commit -F tmp/commit-msg.txt
```

If nothing changed after the gate, skip this step.

### 8. Push the branch

```bash
git push -u origin <branch-name>
```

### 9. Open the PR

Write the PR body to `tmp/pr-body.md` with the Write tool, following `.github/pull_request_template.md` (What / Why / Test plan / Tools, then the cross-cutting-concerns checklist marked done-or-N/A from step 4). End with the `Co-Authored-By:` footer.

Guidelines (AGENTS.md §"Commit and PR style"):
- No `Closes #N` unless a directly related issue exists. Use `Refs #N` for related issues; omit if none.
- PR title: past-tense verb, sentence case, ≤72 chars, no `feat:`/`fix:`/`chore:` prefix. Examples: `"Fixed carry-over spillover to honor lastResetDate"`, `"Added biweekly start-date anchoring to Add Budget screen"`.

```bash
gh pr create --title "<Past-tense subject>" --body-file tmp/pr-body.md
```

Report the PR URL to the user.

## Autonomy

Run all steps without prompting, except when a review finding is genuinely ambiguous about product intent, or when the docs-only CI skip heuristic (step 5) applies (ask before skipping the gate or adding `[skip ci]`). Gate commands, git operations, and `gh pr create` are allowlisted. Translation pipeline runs are autonomous per memory `feedback_localization_autonomous`.

## What this skill does NOT do

- Does not merge. Use `/merge-pr <PR>` after review.
- Does not run `make test-ui` (slow, opt-in via CI comment `/test-full`). Note in the PR body if screen objects were updated and a UI test pass is needed.
- Does not handle OpenSpec changes. If the change needs spec/doc updates, the OpenSpec workflow (`/opsx:verify` → `/opsx:archive`) runs separately after merge.
- Does not involve a GitHub issue. For issue-linked work, use `/create-pr-for-issue <N>`.
