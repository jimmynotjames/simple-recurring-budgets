---
name: appstore-translate-metadata
description: Transcreate the App Store listing from fastlane/metadata/en-US/ into every storefront, then audit and fix it. Use after editing en-US listing copy or when check_metadata.py fails. Does not upload.
---

# Translate App Store metadata

Drives `scripts/translate_metadata/` in subset mode. Run everything from the repo root. Script flags
and file layout: `scripts/translate_metadata/README.md`. In-app strings are `translate-new-strings`.

**Done when** `python3 scripts/translate_metadata/check_metadata.py` exits 0.

Pipeline rules: `localization-spec.md §Running the pipelines` and §Models are pinned deliberately.
Inspect outputs with `validate.py --subset [--json]` and `audit.py [storefront …] [--json]
[--full]`, not `cat`, `jq` or `wc`.

## Sync with `origin/main`

Before anything else, run `git fetch origin`. On `main`, fast-forward when behind (`git pull --ff-only`); uncommitted edits may stay, and if git refuses, stop and ask. On another branch, don't switch or merge: say how far it is behind `origin/main` and confirm before continuing.

## Autonomy

Run end to end without asking between steps, including retries and the step-5 fixes. There are two
human checkpoints, plus the sync step's stops above:

1. **Source-ready confirmation**, before any step. It blocks the run.
2. **Content questions** from step 4a. Surface them in one batch and keep going; they don't block.

## Source-ready confirmation

A slip in the source reaches every storefront, so confirm it first.

1. List `fastlane/metadata/en-US/`. The translatable fields are `TRANSLATABLE_FIELDS` in
   `metadata_locales.py` (i18n/app.json `metadata.translatableFields`, plus `name` when
   `nameMode` is `descriptor`). Read whichever of those files exist. Passthrough files (the URLs,
   and `name.txt` under `nameMode: passthrough`) are copied verbatim, not translated; leave them
   out.
2. Run the voice check:
   ```bash
   python3 scripts/translate_metadata/check_source_voice.py
   ```
   Exit 1 means possible voice slips (exclamation marks, ALL CAPS, superlatives). Don't edit the
   source yourself and don't proceed silently: include every finding (field, token, rule) in the
   confirmation below.
3. In one message, show each translatable field as present or absent, a short preview of each
   present one, and any voice findings. An absent file means the field is unused: merge removes
   that field's file from every storefront. A blank file is an error (`appstore_metadata.py
   validate` rejects it); delete the file instead.
4. Ask the human to confirm the copy is final (`AskUserQuestion` on Claude Code; a short message
   and wait, elsewhere). If they edit, re-read and re-confirm. Don't start step 0 until confirmed.

## 0. Pre-flight

```bash
python3 scripts/pipeline_tmp.py status metadata
python3 scripts/pipeline_tmp.py clean metadata
```

## 1. Detect what needs transcreating

```bash
python3 scripts/translate_metadata/extract.py --missing              # new storefronts or fields
python3 scripts/translate_metadata/extract.py --fields description   # after editing en-US copy
```

Writes `tmp/metadata-inputs/source.json` and `manifest.json` (`{storefront: [fields]}`).
`--missing` finds only absent fields, so after editing an existing en-US field name it with
`--fields` (several allowed). After a register or notes change in a few markets, add
`--storefronts fr-FR ru …` to force the fields there only.

If the manifest is empty, skip steps 2–5 but still run `merge.py` before step 6: it applies any
field removed from en-US.

## 2. Compose per-storefront prompts

```bash
python3 scripts/translate_metadata/dispatch_prompts.py
```

Writes `tmp/metadata-prompts/{storefront}.md`, sliced to that storefront's gaps, and deletes those
storefronts' old outputs.

## 3. Transcreate each storefront

For every `tmp/metadata-prompts/{storefront}.md`, dispatch `subagent_type: metadata-locale`:
"Read `<abs>/tmp/metadata-prompts/de-DE.md` and follow it. Write the JSON object (nothing else) to
`<abs>/tmp/metadata-outputs/de-DE.json`." Never use `general-purpose`. The prompt is complete; if a
rule is missing, fix `PROMPT_TEMPLATE.md`, not the dispatch message.

## 4. Validate, then merge

```bash
python3 scripts/translate_metadata/validate.py --subset
```

Per storefront: **PASS** (ready), **PENDING** (no output yet: dispatch it), or **FAIL** (usually over
the limit, above all `keywords`, whose limit is 100 bytes, not characters: re-dispatch it). Keyword hygiene warnings don't fail.

Retry by re-dispatching only the PENDING and FAIL storefronts. **Don't re-run
`dispatch_prompts.py` mid-fan-out**: it deletes the outputs that already passed.

Once it exits 0:

```bash
python3 scripts/translate_metadata/merge.py
```

## 4a. Content questions

```bash
python3 scripts/translate_metadata/audit.py --questions
```

Agents attach `_questions` only for a real content decision, and always write a best-effort
translation anyway. Present the whole batch in one message, grouped where a question recurs across
storefronts, and ask the human to accept each default or override it. Don't wait on the answers.
If there are none, say so in one line.

For an override, edit `fastlane/metadata/<storefront>/<field>.txt`, or re-dispatch that storefront
with the guidance, then re-run `validate.py` and `check_metadata.py`.

## 5. Semantic audit and remediation

Skip this step if step 1's manifest was empty. Scope: the storefronts in step 1's manifest.
Fixed policy: fix every **medium or high** finding; `low` is advisory. At most **2 rounds**.

1. ```bash
   python3 scripts/translate_metadata/audit_semantic.py --dispatch <storefronts>
   ```
2. For each `tmp/metadata-audit-prompts/{sf}.md`, dispatch `subagent_type: metadata-audit-locale`,
   writing `tmp/metadata-audit-outputs/{sf}.json`.
3. ```bash
   python3 scripts/translate_metadata/audit_semantic.py --report --min-severity medium <storefronts>
   ```
   Exit 0: clean, go to step 6. Exit 1: continue.
4. ```bash
   python3 scripts/translate_metadata/audit_semantic.py --write-manifest --min-severity medium <storefronts>
   python3 scripts/translate_metadata/dispatch_prompts.py
   ```
   This rewrites `tmp/metadata-inputs/` for just the flagged (storefront, field) pairs.
5. For each flagged storefront, dispatch `metadata-locale`: "Read `<abs>/tmp/metadata-prompts/de-DE.md`
   (your task) and `<abs>/tmp/metadata-audit-outputs/de-DE.json` (an auditor's findings on the
   current copy). Fix each finding whose `field` is in your source JSON, ignore the rest, obey every
   prompt rule, and write only the JSON object to `<abs>/tmp/metadata-outputs/de-DE.json`."
6. ```bash
   python3 scripts/translate_metadata/validate.py --subset
   python3 scripts/translate_metadata/merge.py
   ```
   Re-dispatch any PENDING or FAIL storefront before merging.
7. Re-audit only the remediated storefronts (sub-step 1). After round 2, stop: report the remaining
   medium+ findings, grouped, and go to step 6.

## 6. Gate

```bash
python3 scripts/translate_metadata/check_metadata.py
```

It reads `fastlane/metadata/` directly. On gaps, go back to step 1.

## 7. Upload

Not part of this skill: `appstore-push-metadata`.

## 8. Cleanup

Ask first. On a yes (this also clears the `metadata-audit-*` directories):

```bash
python3 scripts/pipeline_tmp.py clean metadata
```
