---
name: /create-pr
id: create-pr
category: Workflow
description: Turn already-written code changes into a reviewed, gated, open PR — no GitHub issue required (the no-issue sibling of /create-pr-for-issue).
---

Turn the already-written changes on the current branch into a **reviewed, gated, open PR**. The implementation is expected to be substantially complete; this command closes the remaining gaps (cross-cutting concerns, review findings, gate) and gets the PR open cleanly.

**Does not merge.** The PR stays open for human review — use `/merge-pr <PR>` once you're satisfied. For issue-linked work, use `/create-pr-for-issue <N>` instead.

Print this checklist unchecked at the start; tick each step as it completes:

1. **Branch** — on a feature branch (create one if on `main`)
2. **Initial commit** — uncommitted changes committed so the diff is reviewable
3. **Fresh-eye review** — full diff reviewed; findings processed
4. **Cross-cutting concerns** — AGENTS.md §6.8 checklist audited against the diff
5. **Gaps fixed** — review findings and cross-cutting gaps addressed
6. **Gate** — four-step gate passes clean
7. **Commit fixes** — any post-review changes committed
8. **Push** — branch pushed to `origin`
9. **PR** — PR opened from `tmp/pr-body.md`; URL reported

## 1. Establish branch state

```bash
git status --short
git branch --show-current
git log --oneline main..HEAD
```

- **On `main` with uncommitted changes**: create a feature branch *now*, before the first `git add` — `git checkout -b u/jimmyho/<tool>/<short-kebab-description>` (lowercase, no underscores; `<tool>` documents authorship, e.g. `cursor` or `cursor+claude`). Moving a commit off `main` later needs a destructive force-push, so branch first.
- **On `main` with commits already on `main`**: requires a force-push to move them onto a branch — stop and ask the user how to proceed.
- **On a feature branch with no commits and nothing uncommitted**: nothing to PR — ask for clarification.
- **On a feature branch with at least one commit or uncommitted changes**: proceed.

## 2. Commit any uncommitted changes

If `git status --short` shows uncommitted changes, stage (use specific file paths, not `git add -A`) and commit them so the review has a clean diff to read.

Write the commit message to a file `tmp/commit-msg.txt`, following the commit subject/body conventions in AGENTS.md §"Commit and PR style", then commit with `git commit -F tmp/commit-msg.txt`. Don't pass the message inline — backticks and newlines force a permission prompt.

## 3. Fresh-eye code review

Get the full branch diff (`git diff main..HEAD`) and review it with fresh eyes for: correctness bugs, data-race or actor-isolation issues, SwiftData model integrity (Sendable, `@ModelActor`, `PersistentIdentifier` usage), architectural problems, and serious extensibility risks. Do **not** flag style issues — the linter owns those.

Process findings by severity:
- **High** — fix now, autonomously. Pause only when a finding is genuinely ambiguous about product intent (you can't determine the right behavior from the surrounding code and PRD).
- **Medium** — fix real bugs and architectural issues; skip subjective preferences or refactors outside the change's scope.
- **Low** — skip (style, premature optimization).

Apply all fixes together.

## 4. Cross-cutting concerns (AGENTS.md §6.8)

For each concern, read the diff to decide whether it applies — a code-reading check, no user input unless genuinely ambiguous.

- **Accessibility** — applies if the diff adds/modifies a SwiftUI `View`. Check: every new composite view has `.accessibilityLabel`/`.accessibilityHint` on interactive or decorative elements; no fixed heights that clip text; destructive controls have `.accessibilityAction(named:)`.
- **Localized source strings** — applies if the diff adds any `Text("…")` literal or UI-facing string. Check: strings use `String(localized:)` or `Text(LocalizedStringResource(…))` with a `comment:`; no hard-coded English in production Views; locale-invariant values (version numbers, ISO codes) use `Text(verbatim:)`.
- **Translations** — applies if any localized key was added or changed. Run `python3 scripts/check_translations.py`; if it exits non-zero, run the `translate-new-strings` pipeline autonomously to bring all 49 locales current before proceeding (the pre-push hook blocks the push otherwise).
- **Mixpanel events** — applies if the diff introduces a new user-initiated action that materially changes app state (new CTA, destructive action, toggle affecting usage/retention). Check: an `AnalyticsClient.track(…)` call per `docs/analytics-spec.md`, no PII.
- **UI test screen objects** — applies if the diff changes navigation, button labels, toolbar items, or sheet routes in any view covered by `simple-recurring-budgetsUITests/`. Check: the relevant screen object (`BudgetsScreen.swift`, `BudgetDetailScreen.swift`, `AddBudgetScreen.swift`, `AddExpenseScreen.swift`, `SettingsScreen.swift`) is updated in the same change. Note in the PR body that `make test-ui` should run before merge.

Fix any gaps you find.

## 5. Run the gate

Run the four-step gate — `make gate` (`make format && make lint-fix && make build && make test`, teed to `tmp/gate.log`) — **in the background**. **Do not open the PR until it's green.** On failure, read `tmp/gate.log`, fix, and re-run. Format/lint output is auto-applied; build/test failures need code changes.

## 6. Commit any post-review changes

If steps 3–5 produced uncommitted edits, stage the specific files, write a message to `tmp/commit-msg.txt` (e.g. `Applied pre-PR review fixes.`), and `git commit -F tmp/commit-msg.txt`. Skip if format/lint applied cleanly to already-committed code.

## 7. Push the branch

```bash
git push -u origin <branch-name>
```

## 8. Open the PR

Write the body to a file `tmp/pr-body.md`, following the structure in `.github/pull_request_template.md` (What / Why / Test plan / Tools, then the cross-cutting-concerns checklist marked done-or-N/A from step 4), ending with the `Co-Authored-By:` footer. Then `gh pr create --title "…" --body-file tmp/pr-body.md` — never pass the body inline via `--body`, because PR bodies contain backticks and newlines that force a permission prompt even though `gh pr *` is allowlisted.

Per AGENTS.md §"Commit and PR style": **no `Closes #N`** unless there's a directly related issue (use `Refs #N` for related, omit if none); PR title follows the subject convention — past-tense verb, sentence case, ≤72 chars, no `feat:`/`fix:`/`chore:` prefix.

Report the PR URL to the user.

## Autonomy & boundaries

Run all steps without prompting, except when a review finding is genuinely ambiguous about product intent. This command does **not**: merge (use `/merge-pr <PR>`); run `make test-ui` (slow, opt-in via a `/test-full` PR comment — note in the body if screen objects changed); handle OpenSpec changes (run `/opsx:verify` → `/opsx:archive` separately); or involve a GitHub issue (use `/create-pr-for-issue <N>`).
