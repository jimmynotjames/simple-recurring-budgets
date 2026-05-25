---
description: Turn a GitHub issue into an open, review-ready PR (front half of the issue-driven workflow).
argument-hint: <issue-number>
---

Take GitHub issue #$1 from report to an open, review-ready PR. Follow the **Issue-driven workflow** front half in `AGENTS.md` exactly:

1. Run `gh issue view $1` (add `--comments` if the thread looks substantive) and restate the problem and your intended fix in a sentence or two before touching code.
2. Create a branch `u/jimmyho/claude-code/<short-description>` off the latest `main`.
3. Implement the fix. If it changes product behavior, specs, or the data model, drive the change through OpenSpec (`/opsx:propose` then `/opsx:apply`) instead of hand-editing specs. For any UI-touching change, satisfy the cross-cutting checklist (accessibility, localized source strings, translations, Mixpanel events).
4. Run the four-step gate: `make format` → `make lint-fix` → `make build` → `make test`. Don't open the PR until it's green.
5. Push the branch and `gh pr create`, using the PR-description template from `AGENTS.md`. Put issue linkage in the body: `Closes #$1` for a complete fix, or `Refs #$1` plus a "what's still pending" note for a partial one.
6. **Stop. Do not merge.** Report the PR URL and a one-line summary, then hand back for manual review. The `/merge-pr-resolve-issue` command lands it after you've reviewed.

If the issue is ambiguous or you find more than one reasonable fix, surface the options and ask before implementing rather than guessing.
