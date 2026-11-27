---
name: audit-translations
description: Grade the existing Localizable.xcstrings translations for tone, register, length and accuracy with per-locale Opus auditors, then hand the flagged strings to translate-new-strings. Adds no translations itself.
---

# Audit translations

Drives `scripts/translate_audit/`. Run everything from the repo root. Script flags, findings shape
and file layout: `scripts/translate_audit/README.md`. New translations are `translate-new-strings`.

Pipeline rules: `localization-spec.md §Running the pipelines` and §Models are pinned deliberately.
The auditor is `translation-audit-locale`, never `general-purpose`.

A `[ratio]` length flag is a heuristic; trust the auditor's `[llm]` length judgment over it.

## Pre-flight

```bash
python3 scripts/pipeline_tmp.py status translate-audit
python3 scripts/pipeline_tmp.py clean translate-audit
```

## 0. Deterministic checks (no LLM, run first)

```bash
python3 scripts/translate_audit/consistency_check.py      # same English, different translations in one locale; --ignore-casing
python3 scripts/translate_audit/plural_completeness.py    # missing or spurious CLDR plural categories
python3 scripts/translate_audit/untranslated_copies.py    # English left in a translated slot
```

`consistency_check.py` and `plural_completeness.py` take `--write-manifest` to emit the pairs for
re-translation. `plural_completeness.py` reads the committed `plural_rules.py`; regenerate it with
`_gen_plural_rules.py`. For each `untranslated_copies.py` finding, either force a re-translation
(`invalidate_keys.py`, since the state is already `translated`) or add it to
`i18n/untranslated_allowlist.json` with the reason.

## 1. Extract current translations

```bash
python3 scripts/translate_audit/audit_extract.py
```

Writes `tmp/translate-audit-inputs/audit_source.json`. Narrow with positional locales (`… de ja`)
or `--keys k1,k2`.

## 2. Compose per-locale audit prompts

```bash
python3 scripts/translate_audit/audit_dispatch.py
```

Writes `tmp/translate-audit-prompts/{locale}.md` and deletes those locales' old outputs. Narrow
with positional locales.

## 3. Audit each locale

For every prompt file, dispatch `subagent_type: translation-audit-locale`: "Read
`<abs>/tmp/translate-audit-prompts/ja.md` and follow it. Write the findings JSON (nothing else) to
`<abs>/tmp/translate-audit-outputs/ja.json`." The prompt is complete; don't add to it.

On a first run, or after changing the template, do steps 1–4 for `de` alone and read
`audit_report.py de` before fanning out. If the findings look wrong, fix `AUDIT_PROMPT_TEMPLATE.md`
or `audit_report.py` first.

## 4. Report

```bash
python3 scripts/translate_audit/audit_report.py --min-severity medium
```

Exit 0 means nothing at or above the threshold. Re-dispatch any locale reported missing or
unreadable.

## 5. Hand the flagged subset to re-translation

```bash
python3 scripts/translate_audit/audit_report.py --write-manifest --min-severity medium
```

Writes `tmp/translate-inputs/{manifest,source}.json` from the `[llm]` findings only. Then run
`translate-new-strings` from its step 2. These are strings the pinned model already got wrong, so
this round may dispatch `translation-locale` with `model: opus` instead of its pinned Sonnet
(`localization-spec.md §Models are pinned deliberately`). Name each locale's findings file in its
dispatch ("…and fix what `<abs>/tmp/translate-audit-outputs/ja.json` flags"), so the translator
sees what was wrong rather than translating blind.

## 6. Re-audit the fix

Re-run steps 1–4 for just those keys and locales (`audit_extract.py --keys … <locales>`). A string
that still flags after one retry stays as it is; list it for owner review instead of looping.

## 7. Cleanup

Ask first. On a yes:

```bash
python3 scripts/pipeline_tmp.py clean translate-audit
```
