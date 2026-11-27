---
name: appstore-translate-metadata
description: Transcreate the App Store listing (name, subtitle, keywords, promotional text, description, release notes) from English into all 49 App Store storefront locales under fastlane/metadata/. Invoked via /appstore:translate-metadata. Use after editing any fastlane/metadata/en-US/*.txt, or when check_metadata.py reports gaps. Drives the scripts/translate_metadata/ pipeline in subset mode with parallel per-storefront Opus subagents, then runs an autonomous Opus semantic-audit + remediation refine pass before the gate. Orchestration is model-light enough to run on Sonnet; the Opus subagents do the translation and audit. This is the App-Store-metadata sibling of translate-new-strings (in-app strings) and appstore-generate-screenshot-seeding (screenshot demo data).
---

# Translate App Store metadata

Canonical recipe for getting `fastlane/metadata/` fully transcreated after
authoring or editing the English (`en-US`) listing copy. Drives the
`scripts/translate_metadata/` pipeline in subset mode.

Done when `python3 scripts/translate_metadata/check_metadata.py` exits 0: every
translatable field the English source has authored is populated and within its
character limit across all 49 target storefronts.

This is the metadata pipeline (App Store listing). For in-app UI strings in
`Localizable.xcstrings`, use `translate-new-strings`. The two use different
locale code systems (storefront vs runtime); `metadata_locales.py` owns the
mapping.

## Preflight — orchestrator model (before anything else)

Run the orchestrator-model preflight first (canonical: `AGENTS.md` →
"Orchestrator-model preflight"). This skill is tuned to orchestrate on Sonnet; if
the session model is not Sonnet, stop and confirm (`AskUserQuestion` on Claude
Code, a markdown block on Cursor) before running anything. Opus is pricier for no
quality gain, and a model weaker than Sonnet may make the Step-5 threshold/loop
judgments unreliable. The `metadata-locale` and `metadata-audit-locale` workers
stay Opus regardless (pinned in their agent definitions), so a Sonnet session
never weakens the translation or audit.

## Preflight — sync with `origin/main` (right after the model preflight)

Start from current `main` so the run doesn't work from stale sources:

```bash
git status --porcelain
git branch --show-current
git fetch origin
git log HEAD..origin/main --oneline
```

- **On `main`, behind `origin/main`**: `git pull --ff-only`. Uncommitted edits
  are fine; git refuses if an incoming commit touches a file you've modified. If
  it refuses or can't fast-forward, stop and ask the user.
- **On another branch**: don't switch or merge. If it's behind `origin/main`,
  say by how many commits and confirm before continuing.


## Autonomy

Run the whole pipeline autonomously, end to end, without pausing for approval on
mechanical steps (extract, dispatch, fan-out, validate, merge, the semantic
audit + remediation loop in Step 5, and the gate; all pre-approved in
`.claude/settings.json`). Don't ask "shall I proceed?" between steps or
permission to retry a failed locale or auto-fix audit findings.

Exactly two deliberate human checkpoints; decide and execute everything else yourself:

1. Up front, before any pipeline step: confirm the English source copy is final
   (the source-ready confirmation below). This is the only gate that blocks the
   run from starting.
2. Mid-run: genuine content questions about the marketing copy that the
   subagents flag (Step 4a). Surface them in a single batch and keep going; they
   refine specific strings and don't block the run.

### Model roles — orchestrator vs. workers

The orchestrator can be Sonnet: every step is a script call, a parallel fan-out,
or a deterministic branch on a PASS/FAIL/severity threshold, with no
orchestrator-level linguistic judgments. All language quality lives in the Opus
worker subagents: `metadata-locale` (transcreation) and `metadata-audit-locale`
(quality audit), both pinned to `model: opus` in their agent definitions; keep
them that way, since they must out-class the copy they produce/grade. Sonnet
orchestrates; Opus translates and audits. Keep the Step-5 thresholds and round
caps fixed rather than deciding per run.

## Hard rules

- Never write ad-hoc Python (`python3 -c`, throwaway `tmp/*.py`) to slice the
  source, filter outputs, or post-process metadata. Every operation has a flag on
  an existing `scripts/translate_metadata/` script. If you reach for inline
  Python, stop and extend a script instead so the permission surface stays narrow.
- Never skip the gate. Anything less than `exit 0` from `check_metadata.py` is
  not done; loop back.
- The brand "Wren" stays verbatim in every locale: never translated,
  transliterated, or glossed. The prompt enforces it and `validate.py` checks it;
  don't "remind" subagents in the dispatch message. Fix `PROMPT_TEMPLATE.md` if a
  rule needs strengthening.
- **RTL storefronts (ar, he, ur):** never start a line with a Latin brand token (`Wren`,
  `iCloud`). In RTL rendering a Latin-initial string pops to the visual end of the line.
  Lead with a native word; the brand may follow mid-sentence.
- Run all commands from the repo root.
- Register notes are intentionally duplicated; keep them in sync, don't DRY them.
  The per-storefront formality guidance in `CULTURAL_NOTES` (`scripts/translate_metadata/dispatch_prompts.py`)
  deliberately overlaps with the in-app `REGIONAL_NOTES` only on the formality decision per
  language (issue #173, closed without consolidation). If you change a market's formality decision
  (e.g. de-DE "du"→"Sie") here, mirror it in `REGIONAL_NOTES`; wording may differ, the formality
  call must not. Don't merge the two maps.

## Source-ready confirmation (human checkpoint — do this first)

The pipeline transcreates every non-empty translatable field in the English
source into all 49 storefronts, so a typo or accidentally-blank field propagates
everywhere and costs a full re-run to undo. Before any pipeline step, confirm the
source with the human; this is the one gate that blocks the run from starting.

**Source location (the only files you edit by hand):**

- **Folder:** `fastlane/metadata/en-US/`
- **Translatable fields:** `name.txt`, `subtitle.txt`, `description.txt`,
  `keywords.txt`, `promotional_text.txt`, `release_notes.txt`
- The `*_url.txt` files (`marketing_url`, `privacy_url`, `support_url`) are copied
  verbatim to every locale, not translated; leave them out of the confirmation.

Read those six files and present, in a single message: the folder path, each
field's current authored / blank state, and a short preview of the authored
values.

Run the source-voice pre-check first (deterministic; don't eyeball it):

```bash
python3 scripts/translate_metadata/check_source_voice.py
```

It scans the authored en-US fields for brand-voice slips that would propagate to
all 49 storefronts and be re-flagged by every semantic auditor: exclamation
marks, ALL-CAPS shouting, and salesy superlatives ("the best", "amazing",
"revolutionary"). Exit 0 = clean, continue. Exit 1 = findings (warnings, not hard
errors): halt and surface every finding to the human as part of the source-ready
prompt below (field, matched token, and the voice rule it breaks), and let them
choose to fix the en-US source first or proceed anyway. Never proceed silently
past a non-zero exit, and never auto-edit the source to "fix" it; the wording is
the human's call.

**WARNING — blank fields clear all translations.** When a translatable field is
blank in `en-US`, `merge.py` erases the content of every existing translated
`.txt` for that field across all storefronts (it reads the blank state straight
from the `en-US` folder), and `check_metadata.py` enforces that those files stay
empty. Intentional (blank in English = blank everywhere), but destructive if the
field is blank by accident.

For any blank field in the summary, display a prominent notice:
> **[BLANK — will erase all existing translated copies of this field]**

Then ask them to confirm the copy is final and ready to transcreate:

- **Claude Code:** `AskUserQuestion`.
- **Cursor:** a short markdown block (mirror the orchestrator-model preflight).

Wait for confirmation before Step 0. If the human wants to edit copy first, let
them, then re-read and re-confirm. This upfront prompt is a deliberate exception
to "run translation work without prompting", specific to this skill because a bad
source string reaches all 49 storefronts.

## Recipe

### 0. Pre-flight — clear stale pipeline outputs

Clear per-storefront leftovers from a previous run. `validate.py` and `merge.py`
read every file in `tmp/metadata-outputs/` (and the audit reads
`tmp/metadata-audit-outputs/`), not just this run's manifest, so stale files
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

`--missing` finds only absent fields, not stale ones. If you edited an existing
en-US field (e.g. rewrote `description.txt`) rather than adding a new locale,
every storefront already has some content for it, so `--missing` reports an
empty manifest and nothing re-translates. To force re-transcreation of edited
field(s) across all 49 storefronts, name them explicitly:

```bash
python3 scripts/translate_metadata/extract.py --fields description   # or: --fields description keywords
```

`--fields` writes the same `manifest.json` shape (all storefronts × the named
fields) and refuses any field that is blank/unknown in the en-US source. Use
`--missing` when filling new locales and `--fields` after editing source copy.
Steps 2–6 are identical either way.

If the manifest is empty, skip Steps 2, 3, 4 (validate), 4a, and 5 (nothing to
refine). But still run `merge.py` (the merge command from Step 4) before the
gate: with no new outputs it merges nothing, but it still scans the `en-US`
source for blank fields and clears existing translated copies of them. Skipping
merge leaves stale translations and makes `check_metadata.py` fail with NOTEMPTY
errors in a loop. After merge, go to the gate (Step 6).

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

> Cross-tool execution: on Claude Code, dispatch one `metadata-locale` subagent per storefront
> in parallel (below). On Cursor or any tool without a subagent primitive, run the same step
> inline and serially: for each `tmp/metadata-prompts/{storefront}.md`, read it, produce the
> transcreation JSON yourself, and write `tmp/metadata-outputs/{storefront}.json`, then continue.
> Same scripts, gates, and result. Canonical: `AGENTS.md > Cross-cutting concerns > Running the
> translation pipelines`.

#### Claude Code — one `metadata-locale` subagent per storefront, in parallel

For every `tmp/metadata-prompts/{storefront}.md` that exists, invoke an `Agent`:

- `subagent_type`: `metadata-locale` (defined in `.claude/agents/metadata-locale.md`,
  Read+Write only, model opus).
- A short dispatch prompt naming the input and output paths. Example:
  > Read `/abs/path/tmp/metadata-prompts/de-DE.md` and follow the rules in it.
  > Write the resulting JSON object (nothing else) to
  > `/abs/path/tmp/metadata-outputs/de-DE.json`.

Don't pass `subagent_type: general-purpose`; the narrow agent keeps the
dispatches auto-approvable in `.claude/settings.json`.

Batch the dispatches and keep agent calls separate from shell/script calls. Send
the subagent calls concurrently in batches (~8–12 per message), not all 49 plus
shell commands in one message. Never mix `Agent` and `Bash` calls in one message:
if one tool call errors (a hygiene-blocked command, a "nothing to commit"), the
whole parallel batch is cancelled, killing in-flight subagents. Run scripts
(extract, dispatch, validate, merge, audit) in their own single-purpose messages,
one command per `Bash` message.

The prompt file already contains every rule (brand, char limits, keywords-as-search,
tone/register, JSON-only). Do not modify it in the dispatch message.

### 4. Validate, then merge

```bash
python3 scripts/translate_metadata/validate.py --subset
```

`--subset` checks only the fields present in each output file and reports one of
three per-storefront states (your retry dashboard):
- **PASS**: valid, within limits, ready to merge.
- **PENDING**: empty/missing output (subagent hasn't run or produced nothing).
  (Re)dispatch that one storefront. Not an error.
- **FAIL**: content produced but broken. Common causes:
  - Over the character limit (`name`/`subtitle` at 30, `keywords` at 100; the
    most common failure): re-dispatch; the prompt tells the model to tighten
    until it fits.
  - `name` missing the brand prefix: re-dispatch.
  - Keyword hygiene warnings (spaces after commas, dupes) are warnings, not
    failures; re-dispatch if egregious.

To retry, re-dispatch only the PENDING/FAIL subagents (the prompt files are
still in `tmp/metadata-prompts/`). Do NOT re-run `dispatch_prompts.py` to
retry: by default it clears every manifest locale's output, wiping locales that
already succeeded. (Re-running the full extract→dispatch→merge loop is safe
because merged locales drop out of the next manifest; only re-running
`dispatch_prompts.py` mid-fan-out is destructive.)

Don't write ad-hoc Python/`wc`/`cat`/`jq` to inspect outputs or count
characters. Two pre-approved tools cover it:
- `validate.py --subset [--json]`: pass/pending/fail + every hard error.
- `audit.py [storefront …]`: per-field char counts vs. limits with OVER flags,
  and the consolidated `_questions` batch (Step 4a). `--json` for a
  machine-readable summary, `--full` for untruncated values.

Once `validate.py --subset` exits 0:

```bash
python3 scripts/translate_metadata/merge.py
```

Writes each field to `fastlane/metadata/{storefront}/{field}.txt` and copies the
URL files verbatim from en-US. Refuses to overwrite an existing non-empty `.txt`
with an empty translated value, but always clears any field that is blank in the
`en-US` source (read directly from the source folder, the same signal the gate
enforces) across all storefronts. The `_questions` array lives only in the
`tmp/metadata-outputs/` JSON; `merge.py` strips `_`-prefixed keys.

### 4a. Collect and surface content questions (the one human checkpoint)

The subagents work autonomously and attach a top-level `_questions` array only
for a genuine content decision about the marketing copy (a concept with no
natural equivalent, a claim that's culturally/legally risky in-market, a
load-bearing phrase that can't fit a 30-char field, or genuinely ambiguous source
English). They always still write a best-effort translation, so the pipeline is
never blocked.

Collect them with the pre-approved tool, not `cat`/`jq`/`python3 -c`:

```bash
python3 scripts/translate_metadata/audit.py --questions
```

It prints every `_questions` entry across all locales (locale, field, issue, and
the subagent's default decision) in one batch, or "No content questions raised".
Present the batch in a single consolidated message (group by issue where the same
question recurs across locales) so the human can accept each default or override
it. Use `AskUserQuestion` (or a concise written summary); don't prompt per
locale, and don't stall the pipeline on answers: the metadata is already merged
and valid, and these questions improve specific strings rather than unblock the
run.

If there are no `_questions` (the expected case), say so briefly and continue.
Don't invent questions or ask for approval you don't need.

If the human overrides a default, apply the change by editing the relevant
`fastlane/metadata/<storefront>/<field>.txt` directly (or re-dispatching that one
locale with the added guidance), then re-run `validate.py` + `check_metadata.py`.

### 5. Semantic quality audit + autonomous remediation (the refine pass)

Merging produces valid copy (within limits, brand-correct), not necessarily good
copy. This step grades the transcreations with an Opus auditor and auto-fixes
what it flags (the quality counterpart to the structural `audit.py`). Run it
autonomously: no prompts, fixed thresholds, bounded rounds.

**Scope.** Audit the storefronts transcreated this run: the keys of the initial
`tmp/metadata-inputs/manifest.json` from Step 1 (all 49 on a full
re-translation, only the touched ones on an incremental run). If Step 1's
manifest was empty, skip this step and go to the gate.

**Fixed policy (don't vary per run):** auto-remediate every finding at severity
medium or high; `low` findings are advisory only. Cap at 2 remediation rounds;
residual medium+ findings after round 2 are surfaced, not looped on.

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
   `tmp/metadata-audit-outputs/{sf}.json`. Batch ~8–12 per message; never mix
   `Agent` and `Bash` calls in one message (a single tool error cancels the
   whole batch and kills in-flight subagents).

3. **Triage:**
   ```bash
   python3 scripts/translate_metadata/audit_semantic.py --report --min-severity medium <storefronts>
   ```
   Exit 0: no medium+ findings; the audit is clean, go to the gate (Step 6).
   Exit 1: findings to fix; continue.

4. **Build the remediation manifest** from the findings:
   ```bash
   python3 scripts/translate_metadata/audit_semantic.py --write-manifest --min-severity medium <storefronts>
   ```
   Writes `tmp/metadata-inputs/{manifest,source}.json` scoped to exactly the
   flagged (storefront, field) pairs, the same shape Step 1 produces.

5. **Regenerate prompts** for the flagged set:
   ```bash
   python3 scripts/translate_metadata/dispatch_prompts.py
   ```
   It reads the remediation manifest and slices each prompt to that storefront's
   flagged fields only.

6. **Re-transcreate with the auditor's feedback.** Fan out one `metadata-locale`
   (Opus) subagent per flagged storefront. In each dispatch message, point the
   agent at both files: its task prompt `tmp/metadata-prompts/{sf}.md` and
   the auditor's findings `tmp/metadata-audit-outputs/{sf}.json`. Instruct it to
   fix each flagged field per the finding's `issue`/`suggestion`, stay within char
   limits and all prompt rules, and write the corrected JSON (flagged fields only)
   to `tmp/metadata-outputs/{sf}.json`. Example:
   > Read `/abs/.../tmp/metadata-prompts/de-DE.md` (your transcreation task) and
   > `/abs/.../tmp/metadata-audit-outputs/de-DE.json` (a prior Opus auditor's
   > findings on the current shipping copy). Produce a corrected transcreation that
   > resolves each finding while obeying every rule in the prompt. Write only the
   > JSON object to `/abs/.../tmp/metadata-outputs/de-DE.json`.

   The findings file may include fields not in your prompt's `## Source fields`
   block (the auditor grades the whole listing; this remediation slice is
   narrower). Act only on findings whose `field` is in your source JSON and
   silently ignore the rest (handled by their own slice or below the remediation
   threshold). Don't add a field the source JSON doesn't contain, and don't spend
   output explaining skipped findings.

7. **Validate + merge** the fixes:
   ```bash
   python3 scripts/translate_metadata/validate.py --subset
   python3 scripts/translate_metadata/merge.py
   ```
   Re-dispatch any PENDING/FAIL storefront (Step 4 of the main recipe) before
   merging.

8. **Re-audit only the remediated storefronts** (back to round step 1 with just
   those). If `--report --min-severity medium <remediated>` exits 0, the refine
   pass is done. If findings remain and you have done fewer than 2 rounds,
   loop. After 2 rounds, stop: print a short residual summary (remaining
   medium+ findings, grouped) for owner review and continue to the gate.

### 6. Authoritative gate

```bash
python3 scripts/translate_metadata/check_metadata.py
```

Walks `fastlane/metadata/` directly (not the tmp/ intermediates), so it
catches anything that didn't merge. If it reports gaps, loop back to step 1
(`extract.py --missing` re-flags exactly what's left).

### 7. Ship (when ready)

Upload metadata only (no binary), or include in a full release:

```bash
fastlane push_metadata
# or flip skip_metadata:false in the `release` lane and run `fastlane release`
```

`push_metadata` / `release` touch App Store Connect; run them only when you
intend to upload. See `fastlane/SETUP.md`.

Expected on the first app version: deliver loads every `release_notes.txt`
then prints `Skipping 'release_notes'... this is the first version of the
app` and doesn't upload it (ASC has no "What's New" field until v1.1). Normal,
not an error; the files upload on the next release. To keep the source
consistent with what's live, `release_notes.txt` stays blank for the first
version (blank en-US source ⇒ blank everywhere, per the gate rule). Author
release notes only from the second version onward.

### 8. Cleanup — offer to clear tmp working files

After the gate is green (and you've shipped or decided not to), offer to clear this
pipeline's gitignored tmp files (both the transcreation and `metadata-audit-*`
working dirs). Ask first; on a yes:

```bash
python3 scripts/pipeline_tmp.py clean metadata
```

## When NOT to use this skill

- Editing in-app UI strings → use `translate-new-strings`.
- Generating App Store screenshot seed content → use
  `/appstore:generate-screenshot-seeding`.
- Capturing + uploading App Store screenshots → use
  `/appstore:generate-push-screenshots`.
