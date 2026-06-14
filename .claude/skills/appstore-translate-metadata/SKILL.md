---
name: appstore-translate-metadata
description: Transcreate the App Store listing (name, subtitle, keywords, promotional text, description, release notes) from English into all 49 App Store storefront locales under fastlane/metadata/. Invoked via /appstore:translate-metadata. Use after editing any fastlane/metadata/en-US/*.txt, or when check_metadata.py reports gaps. Drives the scripts/translate_metadata/ pipeline in subset mode with parallel per-storefront Opus subagents, then runs an autonomous Opus semantic-audit + remediation refine pass before the gate. Orchestration is model-light enough to run on Sonnet; the Opus subagents do the translation and audit. This is the App-Store-metadata sibling of translate-new-strings (in-app strings) and appstore-generate-screenshot-seeding (screenshot demo data).
---

# Translate App Store metadata

Canonical recipe for getting `fastlane/metadata/` to a fully-transcreated state
after authoring or editing the English (`en-US`) listing copy. Drives the
existing `scripts/translate_metadata/` pipeline in subset mode.

**Definition of done:** `python3 scripts/translate_metadata/check_metadata.py`
exits 0 — every translatable field the English source has authored is populated
and within its character limit across all 49 target storefronts.

This is the **metadata** pipeline (App Store listing). For in-app UI strings in
`Localizable.xcstrings`, use the separate `translate-new-strings` skill. They use
different locale code systems (storefront vs runtime); `metadata_locales.py` owns
the mapping.

## Preflight — orchestrator model (before anything else)

Before any other step, run the **orchestrator-model preflight** (canonical:
`AGENTS.md` → "Orchestrator-model preflight"). This skill is tuned to orchestrate on
**Sonnet**; if the current session model is **not** Sonnet, **stop and confirm**
(`AskUserQuestion` on Claude Code, a markdown block on Cursor) before running
anything — Opus works but is pricier for no quality gain, and a model weaker than
Sonnet may make the Step-5 threshold/loop judgments unreliable. The `metadata-locale`
and `metadata-audit-locale` workers stay Opus regardless (pinned in their agent
definitions), so switching the session to Sonnet never weakens the translation or
audit.

## Autonomy

Run this whole pipeline **autonomously, end to end, without pausing for approval
on mechanical steps** — extract, dispatch, fan-out, validate, merge, the semantic
audit + remediation loop (Step 5), and the gate are all routine and pre-approved
in `.claude/settings.json`. Do **not** ask "shall I proceed?" between steps, and do
not ask permission to retry a failed locale or to auto-fix audit findings.

There is exactly **one** thing worth bringing to the human: **genuine content
questions about the marketing copy itself** that the subagents flag (Step 4a).
Surface those in a single batch; everything else you decide and execute yourself.

### Model roles — orchestrator vs. workers

This skill is built so the **orchestrator** (the agent running these steps) can be
**Sonnet**: every step is a script call, a parallel fan-out, or a deterministic
branch on a PASS/FAIL/severity threshold — there are no orchestrator-level
linguistic judgments. All the language quality lives in the **Opus** worker
subagents: `metadata-locale` (transcreation) and `metadata-audit-locale` (quality
audit) are both pinned to `model: opus` in their agent definitions and must stay
that way — they out-class the copy they produce/grade. So: **Sonnet orchestrates,
Opus translates and audits.** Keep the thresholds and round caps in Step 5 fixed
rather than "deciding" per run, so the Sonnet orchestrator never has to judge copy
itself.

## Hard rules

- **Never write ad-hoc Python** (`python3 -c`, throwaway `tmp/*.py`) to slice the
  source, filter outputs, or post-process metadata. Every operation has a flag on
  one of the existing `scripts/translate_metadata/` scripts. If you reach for
  inline Python, **stop** — extend a script instead so the permission surface
  stays narrow.
- **Never skip the gate.** Treat anything less than `exit 0` from
  `check_metadata.py` as not-done and loop back.
- **The brand "Wren" stays verbatim** in every locale — never translated,
  transliterated, or glossed. (This is enforced by the prompt and validated by
  `validate.py`; do not "remind" subagents in the dispatch message — fix
  `PROMPT_TEMPLATE.md` if a rule needs strengthening.)
- **All commands run from the repo root.**
- **Register notes are intentionally duplicated — keep them in sync, don't DRY them.**
  The per-storefront formality guidance in `CULTURAL_NOTES` (`scripts/translate_metadata/dispatch_prompts.py`)
  deliberately overlaps with the in-app `REGIONAL_NOTES` only on the *formality decision* per
  language (issue #173, closed without consolidation). If you change a market's formality decision
  (e.g. de-DE "du"→"Sie") here, mirror it in `REGIONAL_NOTES`; wording may differ, the formality
  call must not. Don't try to merge the two maps.

## Prerequisite: English source copy must exist

The pipeline transcreates whatever non-empty translatable fields exist in
`fastlane/metadata/en-US/`. Before translating, confirm these are authored:
`name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`,
`promotional_text.txt`, `release_notes.txt`. If a field is intentionally blank
(e.g. no promotional text this release), the pipeline simply skips it.

## Recipe

### 0. Pre-flight — clear stale pipeline outputs

Before extracting, clear any per-storefront leftovers from a previous run. `validate.py`
and `merge.py` read **every** file in `tmp/metadata-outputs/` (and the audit reads
`tmp/metadata-audit-outputs/`), not just this run's manifest — so stale files silently
contaminate the run.

```bash
python3 scripts/pipeline_tmp.py status metadata   # inspect leftovers
python3 scripts/pipeline_tmp.py clean metadata    # clear them (allowlisted; no prompt)
```

### 1. Detect what needs transcreating

```bash
python3 scripts/translate_metadata/extract.py --missing
```

Writes:
- `tmp/metadata-inputs/source.json` — every authored en-US field with its value
  and character limit.
- `tmp/metadata-inputs/manifest.json` — `{storefront: [fields...]}` listing the
  gaps to fill.

If the manifest is empty, nothing needs transcreating — skip Steps 2–5 (including
the refine pass; there's nothing new to refine) and go to the gate (Step 6) to
confirm.

### 2. Compose per-storefront prompts

```bash
python3 scripts/translate_metadata/dispatch_prompts.py
```

Writes one ready-to-dispatch prompt per storefront to
`tmp/metadata-prompts/{storefront}.md`, with `{LOCALE_NAME}`, `{LOCALE_CODE}`,
`{CULTURAL_NOTE}`, `{BRAND}`, and `{SOURCE_JSON}` (sliced to that storefront's
gaps, annotated with char limits and per-field guidance) substituted. Also clears
stale output files for those storefronts.

### 3. Transcreate each storefront's slice

> **Cross-tool execution.** On **Claude Code**, dispatch one `metadata-locale` subagent per storefront
> in parallel (below). On **Cursor** or any tool without a subagent primitive, run the same step
> **inline and serially**: for each `tmp/metadata-prompts/{storefront}.md`, read it, produce the
> transcreation JSON yourself, and write `tmp/metadata-outputs/{storefront}.json` — then continue.
> Same scripts, same gates, same result. Canonical: `AGENTS.md > Cross-cutting concerns > Running the
> translation pipelines`.

#### Claude Code — one `metadata-locale` subagent per storefront, in parallel

For every `tmp/metadata-prompts/{storefront}.md` that exists, invoke an `Agent`:

- `subagent_type`: `metadata-locale` (defined in `.claude/agents/metadata-locale.md`,
  Read+Write only, model **opus**).
- A short dispatch prompt naming the input and output paths. Example:
  > Read `/abs/path/tmp/metadata-prompts/de-DE.md` and follow the rules in it.
  > Write the resulting JSON object (nothing else) to
  > `/abs/path/tmp/metadata-outputs/de-DE.json`.

Do not pass `subagent_type: general-purpose` — the narrow agent is what keeps the
dispatches auto-approvable in `.claude/settings.json`.

**Batch the dispatches, and keep agent calls separate from shell/script calls.**
Send the subagent calls concurrently in batches (e.g. ~8–12 per message) rather
than all 49 plus shell commands in one giant message. Never mix `Agent` calls and
`Bash` calls in the same message: if one tool call errors (a hygiene-blocked
command, a "nothing to commit", etc.) the whole parallel batch is cancelled,
killing in-flight subagents and wasting their work. Run scripts (extract,
dispatch, validate, merge, audit) in their own single-purpose messages, and keep
each `Bash` message to one command so one failure can't cascade.

The prompt file already contains every rule (brand, char limits, keywords-as-search,
tone/register, JSON-only). Do not modify it in the dispatch message.

### 4. Validate, then merge

```bash
python3 scripts/translate_metadata/validate.py --subset
```

`--subset` checks only the fields present in each output file and reports one of
three per-storefront states — your retry dashboard:
- **PASS** — valid, within limits, ready to merge.
- **PENDING** — empty/missing output: the subagent hasn't run or produced
  nothing. Action: **(re)dispatch that one storefront.** Not an error.
- **FAIL** — produced content but it's broken. Common causes:
  - **Over the character limit** (especially `name`/`subtitle` at 30, and
    `keywords` at 100 — the single most common failure) — re-dispatch; the prompt
    tells the model to tighten until it fits.
  - **`name` missing the brand prefix** — re-dispatch.
  - **Keyword hygiene warnings** (spaces after commas, dupes) are warnings, not
    failures, but re-dispatch if egregious.

**To retry, re-dispatch only the PENDING/FAIL subagents** (the prompt files are
still in `tmp/metadata-prompts/`). **Do NOT re-run `dispatch_prompts.py` to
retry** — by default it clears every manifest locale's output, wiping locales that
already succeeded. (Re-running the full extract→dispatch→merge loop is safe
because merged locales drop out of the next manifest; it's only re-running
`dispatch_prompts.py` *mid-fan-out* that's destructive.)

**Do not write ad-hoc Python/`wc`/`cat`/`jq` to inspect outputs or count
characters.** Everything you need is in two pre-approved tools:
- `validate.py --subset [--json]` — pass/pending/fail + every hard error.
- `audit.py [storefront …]` — per-field char counts vs. limits with OVER flags,
  and the consolidated `_questions` batch (see Step 4a). Add `--json` for a
  machine-readable summary, `--full` for untruncated values.

Once `validate.py --subset` exits 0:

```bash
python3 scripts/translate_metadata/merge.py
```

Writes each field to `fastlane/metadata/{storefront}/{field}.txt` and copies the
URL files verbatim from en-US. Refuses to clobber a non-empty file with an empty
value. The `_questions` arrays (if any) live only in the `tmp/metadata-outputs/`
JSON — `merge.py` strips `_`-prefixed keys, so they never reach the metadata tree.

### 4a. Collect and surface content questions (the one human checkpoint)

The subagents are instructed to **work autonomously** and only attach a top-level
`_questions` array when they hit a genuine *content* decision about the marketing
copy (a concept with no natural equivalent, a claim that's culturally/legally
risky in-market, a load-bearing phrase that can't fit a 30-char field, or
genuinely ambiguous source English). They always still write a best-effort
translation, so the pipeline is never blocked.

Collect them with the pre-approved tool — **do not hand-roll this with `cat`/`jq`/
`python3 -c`:**

```bash
python3 scripts/translate_metadata/audit.py --questions
```

This prints every `_questions` entry across all locales (locale, field, issue, and
the subagent's default decision) in one batch, or "No content questions raised" if
there are none. Present that batch to the human **in a single consolidated
message** (group by issue where the same question recurs across locales) so they
can accept each default or override it. Use `AskUserQuestion` (or a concise
written summary) — do **not** dribble out one prompt per locale, and do **not**
stall the rest of the pipeline waiting on answers: the metadata is already merged
and valid; these questions are about *improving* specific strings, not unblocking
the run.

If there are **no** `_questions`, say so briefly and continue — this is the
expected case. Do not invent questions or ask for approval you don't need.

If the human overrides a default, apply the change by editing the relevant
`fastlane/metadata/<storefront>/<field>.txt` directly (or re-dispatching that one
locale with the added guidance), then re-run `validate.py` + `check_metadata.py`.

### 5. Semantic quality audit + autonomous remediation (the refine pass)

Merging produces *valid* copy (within limits, brand-correct); it does not mean the
copy is *good*. This step grades the transcreations with an Opus auditor and
auto-fixes what it flags — the quality counterpart to the structural `audit.py`.
Run it **autonomously**: no prompts, fixed thresholds, bounded rounds.

**Scope.** Audit the storefronts you transcreated this run — the keys of the
initial `tmp/metadata-inputs/manifest.json` from Step 1. (On a full re-translation
that's all 49; on an incremental run it's just the touched ones.) If Step 1's
manifest was empty (nothing transcreated), **skip this step** — there is nothing
new to refine — and go to the gate.

**Fixed policy (do not vary per run):** auto-remediate every finding at severity
**medium or high**; `low` findings are advisory only. Cap at **2 remediation
rounds**; residual medium+ findings after round 2 are surfaced, not looped on.

Round protocol:

1. **Dispatch audit prompts** for the in-scope storefronts:
   ```bash
   python3 scripts/translate_metadata/audit_semantic.py --dispatch <storefronts>
   ```
   Writes `tmp/metadata-audit-prompts/{sf}.md` (en source + current localized
   fields + cultural note + limits) and clears their stale audit outputs.

2. **Fan out one `metadata-audit-locale` (Opus) subagent per prompt.** For each
   `tmp/metadata-audit-prompts/{sf}.md`, dispatch `subagent_type:
   metadata-audit-locale` telling it to read that file and write findings JSON to
   `tmp/metadata-audit-outputs/{sf}.json`. Batch ~8–12 per message; **never mix
   `Agent` and `Bash` calls in one message** (a single tool error cancels the
   whole batch and kills in-flight subagents).

3. **Triage:**
   ```bash
   python3 scripts/translate_metadata/audit_semantic.py --report --min-severity medium <storefronts>
   ```
   **Exit 0** → no medium+ findings: the audit is clean, go to the gate (Step 6).
   **Exit 1** → there are findings to fix; continue.

4. **Build the remediation manifest** from the findings:
   ```bash
   python3 scripts/translate_metadata/audit_semantic.py --write-manifest --min-severity medium <storefronts>
   ```
   Writes `tmp/metadata-inputs/{manifest,source}.json` scoped to exactly the
   flagged (storefront, field) pairs — the same shape Step 1 produces.

5. **Regenerate prompts** for the flagged set:
   ```bash
   python3 scripts/translate_metadata/dispatch_prompts.py
   ```
   It reads the remediation manifest and slices each prompt to that storefront's
   flagged fields only.

6. **Re-transcreate with the auditor's feedback.** Fan out one `metadata-locale`
   (Opus) subagent per flagged storefront. In each dispatch message, point the
   agent at **both** files: its task prompt `tmp/metadata-prompts/{sf}.md` **and**
   the auditor's findings `tmp/metadata-audit-outputs/{sf}.json`. Instruct it to
   fix each flagged field per the finding's `issue`/`suggestion`, stay within char
   limits and all prompt rules, and write the corrected JSON (flagged fields only)
   to `tmp/metadata-outputs/{sf}.json`. Example:
   > Read `/abs/.../tmp/metadata-prompts/de-DE.md` (your transcreation task) and
   > `/abs/.../tmp/metadata-audit-outputs/de-DE.json` (a prior Opus auditor's
   > findings on the current shipping copy). Produce a corrected transcreation that
   > resolves each finding while obeying every rule in the prompt. Write only the
   > JSON object to `/abs/.../tmp/metadata-outputs/de-DE.json`.

7. **Validate + merge** the fixes:
   ```bash
   python3 scripts/translate_metadata/validate.py --subset
   python3 scripts/translate_metadata/merge.py
   ```
   Re-dispatch any PENDING/FAIL storefront (Step 4 of the main recipe) before
   merging.

8. **Re-audit only the remediated storefronts** (back to round step 1 with just
   those). If `--report --min-severity medium <remediated>` exits 0, the refine
   pass is done. If findings remain **and** you have done fewer than 2 rounds,
   loop. After 2 rounds, **stop**: print a short residual summary (the remaining
   medium+ findings, grouped) for owner review and continue to the gate — do not
   loop indefinitely.

### 6. Authoritative gate

```bash
python3 scripts/translate_metadata/check_metadata.py
```

This walks `fastlane/metadata/` directly (not the tmp/ intermediates), so it
catches anything that didn't merge. If it reports gaps, loop back to step 1
(`extract.py --missing` will re-flag exactly what's left).

### 7. Ship (when ready)

Upload metadata only (no binary), or include in a full release:

```bash
fastlane push_metadata
# or flip skip_metadata:false in the `release` lane and run `fastlane release`
```

`push_metadata` / `release` touch App Store Connect — only run them when you
actually intend to upload. See `fastlane/SETUP.md`.

### 8. Cleanup — offer to clear tmp working files

After the gate is green (and you've shipped or decided not to), offer to clear this
pipeline's gitignored tmp files (this clears both the transcreation and the
`metadata-audit-*` working dirs). Ask first; on a yes:

```bash
python3 scripts/pipeline_tmp.py clean metadata
```

## When NOT to use this skill

- Editing in-app UI strings → use `translate-new-strings`.
- Generating App Store **screenshot** seed content → use
  `/appstore:generate-screenshot-seeding`.
- Capturing + uploading App Store screenshots → use
  `/appstore:generate-push-screenshots`.
