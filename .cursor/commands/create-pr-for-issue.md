---
name: /create-pr-for-issue
id: create-pr-for-issue
category: Workflow
description: Turn a GitHub issue into an open, review-ready PR (front half of the issue-driven workflow).
---

Take GitHub issue `#<N>` (the issue number you pass to this command) from report to an open, review-ready PR. Follow the **Issue-driven workflow** front half in `AGENTS.md` exactly:

1. Run `gh issue view <N>` (add `--comments` if the thread looks substantive) and restate the problem and your intended fix in a sentence or two before touching code.
2. Create a branch `u/jimmyho/claude-code/<short-description>` off the latest `main`.
3. Implement the fix. If it changes product behavior, specs, or the data model, drive the change through OpenSpec (`/opsx:propose` then `/opsx:apply`) instead of hand-editing specs. For any UI-touching change, satisfy the cross-cutting checklist (accessibility, localized source strings, translations, Mixpanel events).
4. If the fix went through OpenSpec, run `/opsx:verify` and fix everything it flags autonomously. Always run it, even if `/opsx:apply` already verified — apply's check is not a substitute.
5. Do a fresh-eye code review of the full branch diff and fix what you find autonomously: correctness bugs, architectural problems, and serious future-extensibility risks (not style nits the linter owns). Exercise best judgment; only stop to ask if a finding genuinely needs the user's call. This runs **after** the OpenSpec verify in step 4.
6. Run the four-step gate: `make format` → `make lint-fix` → `make build` → `make test`. Re-run after any step-4/5 fixes. Don't open the PR until it's green.
7. Push the branch and open the PR. **Write the body to a file `tmp/pr-body.md`, then `gh pr create --title "…" --body-file tmp/pr-body.md`** — never pass the body inline via `--body`, because PR bodies contain backticks (command-substitution syntax) and newlines that force a permission prompt even though `gh pr *` is allowlisted. Use the PR-description template from `AGENTS.md`, with issue linkage in the body: `Closes #<N>` for a complete fix, or `Refs #<N>` plus a "what's still pending" note for a partial one.
8. **Stop. Do not merge.** Report the PR URL and a one-line summary, then hand back for manual review. The `/merge-pr` command lands it after you've reviewed.

If the issue is ambiguous or you find more than one reasonable fix, surface the options and ask before implementing rather than guessing.
