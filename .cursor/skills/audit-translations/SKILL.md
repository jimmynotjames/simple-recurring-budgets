---
name: audit-translations
description: Audit the existing non-English translations in Localizable.xcstrings for quality — tone, formality register, cultural appropriateness, length/truncation risk, and accuracy — then emit a re-translation manifest for the flagged subset. Drives the scripts/translate_audit/ pipeline with parallel per-locale Opus subagents. Use to run a translation quality audit, or to re-check specific locales/keys after re-translating.
---

# Audit translations

Grades the translations already in `Localizable.xcstrings` (it does **not** create new ones —
that's the `translate-new-strings` skill). Drives the `scripts/translate_audit/` pipeline:
extract current translations → fan out one Opus auditor per locale → aggregate findings →
optionally hand the flagged subset to the re-translation flow.

Authoritative design + status: `docs/audits/translation-quality-audit-2026-06-02.md`.
Script reference: `scripts/translate_audit/README.md`.

## Hard rules

- **Never write ad-hoc Python** (`python3 -c`, throwaway `tmp/*.py`) to slice the source,
  filter findings, or build the manifest. Every operation is a flag on one of the four
  scripts; if you reach for inline Python, extend a script instead.
- **The auditor must be Opus.** Dispatch `subagent_type: translation-audit-locale` (defined
  in `.claude/agents/translation-audit-locale.md`, pinned to `model: opus`). It must out-class
  the model that produced the translations, or it adds no signal. Do not substitute
  `general-purpose`.
- **Audit ≠ verdict for `[ratio]` findings.** The deterministic length flag is a heuristic;
  trust the auditor's `[llm]` length judgment over a raw ratio.
- **All commands run from repo root.**
- **The register rubric is reused, not owned, here.** This audit grades against the in-app
  `REGIONAL_NOTES`, which by design duplicates only the *formality decision* with the metadata
  pipeline's `CULTURAL_NOTES` (issue #173, closed without consolidation). Nothing to do here
  beyond awareness — don't propose merging the two register maps; they're kept in sync by
  convention.

## Recipe

### Pre-flight — clear stale pipeline outputs

Before extracting, clear any per-locale leftovers from a previous run. `audit_report.py`
reads **every** file in `tmp/translate-audit-outputs/`, not just this run's locales — so
stale findings from a prior run silently skew the report.

```bash
python3 scripts/pipeline_tmp.py status translate-audit   # inspect leftovers
python3 scripts/pipeline_tmp.py clean translate-audit    # clear them (allowlisted; no prompt)
```

### 0. Deterministic consistency check (no LLM — run first)

```bash
python3 scripts/translate_audit/consistency_check.py            # report
python3 scripts/translate_audit/consistency_check.py --ignore-casing   # word-choice only
```
Finds keys that share the same English but got **different** translations within a locale
("Add Funds" → two renderings in de). This is free and exact — run it before the LLM fan-out. To
fix divergences, `--write-manifest` emits the divergent set for the glossary-aware translate flow
(see the glossary docs in `scripts/translate_catalog/README.md`). The LLM auditor independently
raises `category: consistency` findings; the two complement each other.

Also run the deterministic **plural-completeness** check (no LLM):
```bash
python3 scripts/translate_audit/plural_completeness.py          # report (--write-manifest to fix)
```
For every plural key it flags locales missing a CLDR-required category or carrying a spurious one
(the LLM auditor is unreliable here — it missed Arabic shipping only `one/other`). `--write-manifest`
emits the incomplete pairs for re-translation. The required set is the integer-reachable CLDR
categories per locale, from the committed `plural_rules.py` (regenerate via `_gen_plural_rules.py`).

Also run the deterministic **untranslated-copy** check (no LLM):
```bash
python3 scripts/translate_audit/untranslated_copies.py          # report
```
It flags a locale whose value is byte-identical to the English source on a key translated in nearly
every other locale — English left in a non-English slot under a `translated` state, which the
state-based `check_translations.py` gate can't see (this is how Hindi shipped "Specific Dates"). It
excludes en-* variants and broadly-kept loanwords/brand terms; confirmed cognates live in its
`ALLOWLIST`. Triage each finding: translate it (force, since the state is already `translated`) or
allowlist it with the reason.

### 1. Extract current translations

```bash
python3 scripts/translate_audit/audit_extract.py
```
Writes `tmp/translate-audit-inputs/audit_source.json` (English + comment + format specifiers +
every locale's current translation). Restrict with positional locales (`… de ja`) or
`--keys k1,k2` for a targeted re-audit.

### 2. Compose per-locale audit prompts

```bash
python3 scripts/translate_audit/audit_dispatch.py
```
Writes one `tmp/translate-audit-prompts/{locale}.md` per locale (all locales that have a
translation), and clears stale outputs for those locales. Restrict with positional locales.

### 3. Audit each locale's slice

> **Cross-tool execution.** On **Claude Code**, dispatch one `translation-audit-locale` (Opus)
> subagent per locale in parallel (below). On **Cursor** or any tool without a subagent primitive,
> run the same step **inline and serially**: for each `tmp/translate-audit-prompts/{locale}.md`, read
> it, produce the findings JSON yourself, and write `tmp/translate-audit-outputs/{locale}.json` — then
> continue to step 4. Same scripts, same result. Canonical: `AGENTS.md > Cross-cutting concerns >
> Running the translation pipelines`.

#### Claude Code — one `translation-audit-locale` subagent per locale, in parallel

For every `tmp/translate-audit-prompts/{locale}.md`, invoke an `Agent` with
`subagent_type: translation-audit-locale` and a short dispatch prompt, e.g.:
> Read `/abs/path/tmp/translate-audit-prompts/ja.md` and follow the rubric in it. Write the
> findings JSON (nothing else) to `/abs/path/tmp/translate-audit-outputs/ja.json`.

**Send all subagent calls in a single message** so they run concurrently. The prompt already
contains the full rubric, the locale's regional note, and (when `glossary.json` is populated) the
agreed glossary translations for terms in that slice — so the auditor can raise `consistency`
findings. Do not modify it.

**Dry-run first.** On the initial run, do step 1–3 for a single locale (`de`) and check
`audit_report.py de` before fanning out to all 49 — if the findings shape or signal looks
off, fix `AUDIT_PROMPT_TEMPLATE.md`/`audit_report.py` first.

### 4. Aggregate into a triage report

```bash
python3 scripts/translate_audit/audit_report.py                      # everything
python3 scripts/translate_audit/audit_report.py --min-severity medium
```
Groups findings by severity then locale, tags each `[llm]` or `[ratio]`, and prints
per-locale auditor summaries. Exit 0 = nothing at/above the threshold. Re-dispatch any locale
flagged as missing/unreadable.

### 5. Hand the flagged subset to re-translation (Track C)

```bash
python3 scripts/translate_audit/audit_report.py --write-manifest --min-severity medium
```
Writes `tmp/translate-inputs/{manifest,source}.json` in the exact shape
`extract.py --missing` produces. The manifest contains only the auditor's `[llm]`-judged
findings; `[ratio]` length flags are advisory (heuristic, not a verdict) and are **excluded**
from re-translation — genuine length problems already reach it as `[llm]` `length` findings.
Then run the **`translate-new-strings`** skill from its
step 2 onward (`dispatch_prompts.py` → fan out `translation-locale` → `validate.py --subset`
→ `merge.py`) to re-translate exactly those (key, locale) pairs — **use a stronger model**
(`model: sonnet`/`opus`) on the `translation-locale` dispatches for this round, since these
are the strings the original model got wrong.

### 6. Re-audit the fix

Re-run steps 1–4 restricted to the re-translated keys/locales
(`audit_extract.py --keys … <locales>`) to confirm the findings cleared. Leave a string that
still flags after one retry as-is and note it for owner review rather than looping.

### 7. Cleanup — offer to clear tmp working files

After reporting (and handing any flagged subset to re-translation), offer to clear this
audit's gitignored tmp files. Ask first; on a yes:

```bash
python3 scripts/pipeline_tmp.py clean translate-audit
```

(If you handed a subset to `translate-new-strings`, that skill cleans the `translate`
group separately.)

## File layout reference

```
scripts/translate_audit/
  audit_extract.py        # step 1: catalog → audit_source.json (incl. current translations)
  AUDIT_PROMPT_TEMPLATE.md# auditor prompt template
  audit_dispatch.py       # step 2: template + source → tmp/translate-audit-prompts/
  audit_report.py         # step 4/5: aggregate findings; --write-manifest for re-translation
  README.md               # script reference

.claude/agents/
  translation-audit-locale.md   # step 3 subagent (Read+Write, Opus)

tmp/
  translate-audit-inputs/audit_source.json
  translate-audit-prompts/{locale}.md
  translate-audit-outputs/{locale}.json
  translate-inputs/{manifest,source}.json   # step 5 hand-off to translate-new-strings
```
