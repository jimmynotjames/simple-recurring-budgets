---
name: create-pr-for-issue
description: Turn a GitHub issue into an open, review-ready PR. Implements the fix, runs OpenSpec verify/archive when applicable, fresh-eye review, cross-cutting checks, gate, push, and PR with Closes #N linkage. Does NOT merge; pair with /merge-pr after review. Invoked via /create-pr-for-issue <N>.
---

# Create PR for issue

Takes GitHub issue `#<N>` from report to an open, review-ready PR. The issue number is passed when invoking this skill.

**Does not merge.** Report the PR URL and hand back for manual review. Use `/merge-pr <PR>` after you're satisfied.

## Progress checklist

Print this unchecked at the start; tick each step as it completes.

1. **Issue** — problem restated; intended fix clear
2. **Branch** — feature branch off latest `main`
3. **Implement** — fix landed; OpenSpec when required
4. **Verify** — `/opsx:verify` clean (if OpenSpec change)
5. **Fresh-eye review** — full diff reviewed; findings fixed
6. **Docs-only CI** — user confirmed skip or proceed normally
7. **Gate** — four-step gate green *(or skipped after docs-only confirmation)*
8. **Archive** — OpenSpec archived in-branch or deferred (noted in PR)
9. **Push & PR** — branch pushed; PR opened with `Closes #<N>` or `Refs #<N>`

## Recipe

### 1. Understand the issue

```bash
gh issue view <N>
```

Add `--comments` if the thread looks substantive. Restate the problem and your intended fix in a sentence or two **before** touching code.

If the issue is ambiguous or you find more than one reasonable fix, surface the options and ask before implementing rather than guessing.

### 2. Create a branch

Off the latest `main`:

```bash
git checkout main
git pull --ff-only
git checkout -b u/jimmyho/<tool>/<short-kebab-description>
```

Branch name format: `u/jimmyho/<tool>/<short-kebab-description>`, all lowercase, no underscores. `<tool>` documents authorship (e.g. `cursor`, `claude-code`, `cursor+claude`).

### 3. Implement the fix

If the change touches product behavior, specs, or the data model, drive it through OpenSpec (`/opsx:propose` then `/opsx:apply`) instead of hand-editing specs.

For any UI-touching change, satisfy the cross-cutting checklist as you implement (accessibility, localized source strings, translations, Mixpanel events, UI test screen objects — see `create-pr` skill step 4 or AGENTS.md §6.8).

### 4. OpenSpec verify (when applicable)

If the fix went through OpenSpec, run `/opsx:verify` and fix everything it flags autonomously. **Always** run it, even if `/opsx:apply` already verified — apply's check is not a substitute.

### 5. Fresh-eye code review

Get the full branch diff:
```bash
git diff main..HEAD
```

Review for correctness bugs, architectural problems, and serious future-extensibility risks (not style nits the linter owns). Exercise best judgment; only stop to ask if a finding genuinely needs the user's call. Fix what you find autonomously.

**Cross-tool execution.** Claude Code: spawn a `general-purpose` subagent with the same brief as the `create-pr` skill (step 3). Cursor: review inline in the same session — no subagent fan-out.

Process findings by severity:
- **High** — fix now, autonomously.
- **Medium** — fix real bugs and architectural issues; skip subjective preferences outside scope.
- **Low** — skip (style, premature optimization).

### 6. Docs-only? Confirm CI skip (heuristic)

Before the gate, run `git diff main..HEAD --name-only`. If **every** changed path looks documentation-only (e.g. `docs/**`, `*.md`, `openspec/**`, `.cursor/**`, `.claude/**`, `.github/**/*.md`), **stop and ask the user**:

> This looks like a documentation-only change. Add `[skip ci]` to the commit message before push to skip GitHub Actions? (Heuristic — not 100% reliable.)

- **If yes:** ensure the HEAD commit includes `[skip ci]` (amend or follow-up commit). You may skip the local gate (step 7).
- **If no:** proceed with the gate and a normal commit message.

Never skip silently; user confirmation is required.

### 7. Run the gate

```bash
make gate
```

Run in the background (`run_in_background: true`) unless step 6 confirmed a docs-only skip. Re-run after any step-5 fixes. **Do not open the PR until it's green.**

On failure: read `tmp/gate.log`, fix, and re-run.

### 8. OpenSpec archive (when applicable)

If the fix went through OpenSpec **and you're confident the work fully meets expectations**, **archive in this same branch before opening the PR**: run `/opsx:archive <name>`, which syncs delta specs into main specs and moves the change to `openspec/changes/archive/<date>-<name>/`. Archive is markdown-only — no re-run of the gate needed.

**If confidence is incomplete** — e.g. manual verification pending, or review may change the work — **defer archiving to merge time**: leave the change active, note in the PR body that archive is intentionally deferred, and `/merge-pr` will prompt to finish it. Either way it stays in **one** PR; never split archive into a follow-up PR.

### 9. Push and open the PR

```bash
git push -u origin <branch-name>
```

Write the PR body to `tmp/pr-body.md` using the **Write tool**, following `.github/pull_request_template.md` (What / Why / Test plan / Tools, then cross-cutting checklist). Issue linkage:

- **`Closes #<N>`** — complete fix (auto-closes on squash-merge)
- **`Refs #<N>`** — partial fix; note what's still pending

Create the PR:
```bash
gh pr create --title "<Past-tense subject>" --body-file tmp/pr-body.md
```

PR title: past-tense verb, sentence case, ≤72 chars, no conventional-commit prefix (AGENTS.md §"Commit and PR style").

Report the PR URL and a one-line summary. **Stop — do not merge.**

## Autonomy

Run all steps without prompting, except when: the issue is ambiguous; a review finding needs the user's call; or the docs-only CI skip heuristic (step 6) applies.

## What this skill does NOT do

- **Does not merge.** Use `/merge-pr <PR>` after review.
- **Does not replace `/create-pr`.** Use `create-pr` when code is already written and no issue drives the work.
