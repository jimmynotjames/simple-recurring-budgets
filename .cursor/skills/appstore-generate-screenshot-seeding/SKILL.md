---
name: appstore-generate-screenshot-seeding
description: Generate the culturally-tuned, per-locale demo content (the "seeding" data) the Wren app is seeded with when capturing App Store screenshots (≤3 budgets per locale with locally realistic names, emoji, currency, and amounts). Drives the scripts/screenshot_content/ pipeline with parallel per-storefront Opus subagents and writes the runtime-keyed catalog under simple-recurring-budgetsUITests/ScreenshotSeeds/. Invoked via /appstore:generate-screenshot-seeding. Use before capturing localized screenshots, or after editing SOURCE.json. This generates seed content only; capture + upload is the sibling /appstore:generate-push-screenshots.
---

# Generate App Store screenshot demo-content

Canonical recipe for filling the per-locale screenshot demo-content catalog the
`AppStoreScreenshots` UI test seeds from. Drives `scripts/screenshot_content/`.

Done when `python3 scripts/screenshot_content/check_content.py`
exits 0: every runtime locale (en-US + 49 targets) has a well-formed catalog
entry under `simple-recurring-budgetsUITests/ScreenshotSeeds/`.

This is the screenshot demo-content pipeline. Siblings: in-app UI strings →
`translate-new-strings`; App Store text metadata → `/appstore:translate-metadata`.
All three target the same markets with different artifacts; `metadata_locales.py`
owns the runtime↔storefront mapping that `content_locales.py` reuses.

## "Regenerate screenshots" ≠ regenerate this content

When the user asks to "regenerate" / "redo" / "refresh" screenshots, the
default reading is to re-run the capture (`fastlane screenshots`) against the
existing committed catalog, not this content pipeline. Treat it as a
content request only when the user explicitly names the seed content ("seed content",
"demo budgets/data", "ScreenshotSeeds", "locale content", "SOURCE.json").

If the wording could plausibly mean either, ask one clarification question
before running anything ("Re-capture the screenshots from the existing seed
catalog, or regenerate the seed content itself?"); if no answer is
available, lean strongly toward re-capture.

## When to regenerate content

The committed catalog is curated and human-validated: once screenshots built
from it are inspected and shipped, the content is approved; don't churn it.
Regeneration is nondeterministic, so every run replaces approved content with
different-but-equivalent content and forces a fresh ~2 h capture, a 500-shot
re-inspection, and a re-upload.

- Default (`extract.py --missing`): fill only absent/empty locales (e.g.
  new storefronts after a locale expansion). Removed locales just lose their file.
- `SOURCE.json` changed: the structural contract derives from it, so
  regenerate everything (full manifest).
- One locale is wrong or aging (e.g. inflation makes its anchored amounts
  look stale): regenerate just that storefront via locale args.
- Full overwrite-regeneration of all locales is exceptional: only on an
  explicit, unambiguous user request for fresh content everywhere.

## Preflight — orchestrator model (before anything else)

Run the orchestrator-model preflight first (canonical: `AGENTS.md` →
"Orchestrator-model preflight"). This skill is tuned to orchestrate on Sonnet; if
the session model is not Sonnet, stop and confirm (`AskUserQuestion` on Claude
Code, a markdown block on Cursor) before running anything. Opus is pricier for no
quality gain, and a model weaker than Sonnet may make the validate/retry
judgments unreliable. The `screenshot-content-locale` workers stay Opus
regardless (pinned in their agent definition), so a Sonnet session never weakens
the generated content.

## Autonomy

Run end to end autonomously, without pausing on mechanical steps (extract,
dispatch, fan-out, validate, merge, gate). Don't ask "shall I proceed?" between
steps or permission to retry a failed locale.

Apart from the sync preflight's stops, surface only genuine `_questions` the subagents flag (a market whose real
currency differs from the default, or a dropped third budget), in a single
consolidated batch; decide everything else yourself.

## Preflight — sync with `origin/main` (right after the model preflight)

Start from current `main` so the run doesn't work from stale sources:

```bash
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **On `main`, behind `origin/main`**: `git pull --ff-only`. Uncommitted edits
  are fine; git refuses if an incoming commit touches a file you've modified. If
  it refuses or can't fast-forward, stop and ask the user.
- **On another branch**: don't switch or merge. If it's behind `origin/main`,
  say by how many commits and confirm before continuing.


## Progress reporting

Autonomous is not silent. Narrate the run as a fixed checklist so the user can
see where the job is. Steps (matching the Recipe below):

0. **Model preflight** — confirm session is Sonnet (else confirm before proceeding);
   then sync with `origin/main`
1. **Pre-flight** — clear stale `tmp/screenshot-content-*` outputs
2. **Extract** — stage source, compute the work manifest
3. **Prompts** — compose per-storefront prompt files
4. **Generate** — fan out one subagent per storefront
5. **Validate** — per-storefront PASS dashboard (re-dispatch PENDING/FAIL until clean)
6. **Questions** — consolidated `_questions` checkpoint (report "none" explicitly)
7. **Merge** — write the runtime-keyed catalog
8. **Gate** — `check_content.py` exits 0
9. **Cleanup** — offer to clear tmp working files

Protocol:

- At job start, print the full numbered checklist (all unchecked). Omit steps that provably won't run (e.g.
  an empty manifest skips 3–7) and say why.
- When a step starts, say in one line what it will do (e.g. "Starting 4. Generate — dispatching 49 subagents in 5 batches").
- When a step completes, re-print the full checklist with completed steps
  checked (`- [x]`) and a one-line result on each (counts, PASS/FAIL tallies,
  file paths). The current step stays unchecked with "in progress"; for the
  long fan-out step, update as each dispatch batch's completions arrive (e.g.
  "32/49 outputs written"), not only at the end.

Keep each reprint to one line per step. Never pause for acknowledgement between steps.

## Hard rules

- Never write ad-hoc Python to slice the source or post-process outputs. Every
  operation is a flag on a `scripts/screenshot_content/` script; extend a script
  instead of inline `python3 -c` / throwaway `tmp/*.py`.
- Never skip the gate. Anything less than `exit 0` from `check_content.py` is
  not done; loop back.
- The structural contract is fixed. `role`, `period`, `startOffsetDays`,
  `isCarryOverEnabled`, expense count, and each expense's `daysAgo` come from
  `SOURCE.json` and must be preserved per locale (the prompt + `validate.py`
  enforce this). Only content (names, emoji, currency, amounts) is tuned.
- Amounts are locally realistic, never FX-converted. Enforced by the prompt's
  anchor table and human inspection of the screenshots later.
- Run all commands from the repo root.

## Recipe

### 1. Pre-flight — clear stale pipeline outputs

Clear per-storefront leftovers from a previous run. `validate.py` and `merge.py`
read every file in `tmp/screenshot-content-outputs/`, not just this run's
manifest, so stale files contaminate the run. (Clears only the gitignored
`tmp/screenshot-content-*` working dirs, never the committed `ScreenshotSeeds/`
catalog.)

```bash
python3 scripts/pipeline_tmp.py status screenshot-content   # inspect leftovers
python3 scripts/pipeline_tmp.py clean screenshot-content    # clear them (allowlisted; no prompt)
```

### 2. Extract — detect what needs generating

```bash
python3 scripts/screenshot_content/extract.py --missing
```

Stages `tmp/screenshot-content-inputs/source.json` and writes a manifest of the
storefronts whose runtime catalog entry is absent/empty. If the manifest is empty,
skip to step 8 (Gate).

### 3. Prompts — compose per-storefront prompts

```bash
python3 scripts/screenshot_content/dispatch_prompts.py
```

Writes one prompt per storefront to `tmp/screenshot-content-prompts/{storefront}.md`
(template + market currency + decimals + reused `CULTURAL_NOTES` + source), and
clears stale outputs for those storefronts.

### 4. Generate — each storefront's content

> Cross-tool execution: on Claude Code, dispatch one
> `screenshot-content-locale` subagent per storefront in parallel (below). On
> Cursor or any tool without a subagent primitive, do the same inline and
> serially: for each `tmp/screenshot-content-prompts/{storefront}.md`, read it,
> produce the JSON yourself, and write `tmp/screenshot-content-outputs/{storefront}.json`.

#### Claude Code — one `screenshot-content-locale` subagent per storefront

For every `tmp/screenshot-content-prompts/{storefront}.md`, invoke an `Agent`:

- `subagent_type`: `screenshot-content-locale` (defined in
  `.claude/agents/screenshot-content-locale.md`, Read+Write only, model opus).
- A short dispatch prompt naming the input and output paths, e.g.:
  > Read `/abs/path/tmp/screenshot-content-prompts/ja.md` and follow the rules in
  > it. Write the resulting JSON object (nothing else) to
  > `/abs/path/tmp/screenshot-content-outputs/ja.json`.

Batch the dispatches (~8–12 per message) and never mix `Agent` calls with `Bash`
calls in one message: if one tool call errors, the whole parallel batch is
cancelled, killing in-flight subagents. Run scripts in their own single-command
messages.

### 5. Validate

```bash
python3 scripts/screenshot_content/validate.py --subset
```

Reports PASS / WARN / PENDING / FAIL per storefront (your retry dashboard).
Re-dispatch only the PENDING/FAIL subagents (their prompt files are still in
`tmp/screenshot-content-prompts/`). Don't re-run `dispatch_prompts.py`
mid-fan-out: it clears outputs by default and would wipe locales that succeeded.
This step is done when `validate.py --subset` exits 0.

### 6. Questions — surface content questions (the one human checkpoint)

If any output JSON has a `_questions` array, collect them and present them in a
single consolidated message (group by recurring issue) so the user can accept
each default or override it. If there are none (the expected case), say so
briefly and continue. Don't invent questions or stall the pipeline.

To apply an override, edit the relevant `tmp/screenshot-content-outputs/{storefront}.json`
(or re-dispatch that one locale with added guidance), then re-run `validate.py` +
`merge.py`.

### 7. Merge

```bash
python3 scripts/screenshot_content/merge.py
```

Writes each storefront's runtime-keyed catalog file and (re)writes the en-US entry
from source. `_questions` arrays live only in `tmp/screenshot-content-outputs/`;
`merge.py` writes `budgets` plus a top-level `primaryLocale` (the region-qualified
`-AppleLocale`, e.g. `de_DE`, that makes the Settings currency-display example show
the market's currency). To resync `primaryLocale` into the committed catalog
without regenerating content (e.g. after editing `REGION_BY_STOREFRONT`), run
`python3 scripts/screenshot_content/set_primary_locales.py`.

### 8. Gate

```bash
python3 scripts/screenshot_content/check_content.py
```

Walks the catalog directly. If it reports gaps, loop back to step 2
(`extract.py --missing` re-flags exactly what's left).

### Capture and upload screenshots (separate skill)

This skill stops once the seed catalog is green. Capturing (`fastlane screenshots`)
and uploading to App Store Connect belong to `/appstore:generate-push-screenshots`,
the next step after this gate. Don't run `fastlane screenshots` from here.

### 9. Cleanup — offer to clear tmp working files

After `check_content.py` is green (tmp outputs are no longer needed), offer to clear this pipeline's gitignored tmp files. Ask first; on a yes:

```bash
python3 scripts/pipeline_tmp.py clean screenshot-content
```

## When NOT to use this skill

- App Store text metadata → `/appstore:translate-metadata`.
- In-app UI strings → `translate-new-strings`.
- Capturing and uploading screenshots → `/appstore:generate-push-screenshots`.
