# Translation audit pipeline

Audits the **existing** non-English translations in the app's
`Localizable.xcstrings` (i18n/app.json `paths.catalog`) for **quality** — tone, formality
register, cultural appropriateness, length/truncation risk, and accuracy — and produces a
triage report plus a re-translation manifest for the strings that need fixing.

This is the quality-audit sibling of `scripts/translate_catalog/` (which *creates* and
*structurally validates* translations). The two are deliberately separate:

- `scripts/translate_catalog/` = produce + structurally gate translations (the
  `translate-new-strings` skill).
- `scripts/translate_audit/` (this folder) = grade the translations already in the catalog
  (the `audit-translations` skill).

It imports the catalog pipeline's `locales.py` (`LOCALES`, `LOCALE_NAMES`) and the in-app
notes (`i18n/regional_notes.json`, via `dispatch_prompts.py`), so the auditor grades against the
same per-locale rubric the translator was given. Python 3 stdlib only. Why the in-app and store
notes are separate maps: the repo's localization spec (i18n/app.json `spec`).

Keys under an app's demo-content namespaces (i18n/app.json `transcreatedNamespaces`) are
transcreated rather than translated: the auditor grades them on cultural fit, not fidelity to the
English (`AUDIT_PROMPT_TEMPLATE.md`).

## Scripts

| Script | Purpose |
|---|---|
| `audit_extract.py` | Read the catalog → write `tmp/translate-audit-inputs/audit_source.json` (English source + comment + format specifiers + **every locale's current translation**). |
| `AUDIT_PROMPT_TEMPLATE.md` | Per-locale auditor prompt template (placeholders substituted by `audit_dispatch.py`): the tone/register/length/accuracy rubric + the locale's regional note + the source block. |
| `audit_dispatch.py` | Compose ready-to-dispatch per-locale audit prompts in `tmp/translate-audit-prompts/{locale}.md`. |
| `audit_report.py` | Aggregate the per-locale findings into a triage report; deterministic length pre-filter; `--write-manifest` to feed the re-translation step. Categories are free-form, incl. `consistency`. |
| `consistency_check.py` | **Deterministic** (no LLM): find keys that share the same English but got different translations within a locale. Tags `word-choice` vs `casing-only`; `--write-manifest` for the glossary-aware re-translation. Run it before the LLM fan-out. |
| `plural_completeness.py` | **Deterministic** (no LLM): for every plural key, flag locales missing a CLDR-required plural category or carrying a spurious one; `--write-manifest` to re-translate. Required set = integer-reachable CLDR categories from the committed `plural_rules.py`. |
| `untranslated_copies.py` | **Deterministic** (no LLM): flag a locale whose value is byte-identical to the English source on a key that's translated in nearly every other locale — i.e. English left in a non-English slot under a `translated` state (which `check_translations.py` can't see). Excludes en-* variants and broadly-kept loanwords/brand terms; residual legit cognates live in `i18n/untranslated_allowlist.json`. Triage each: translate (force) or allowlist. |
| `plural_rules.py` | Generated per-locale CLDR plural categories (`required` integer-reachable + `valid` full set). Regenerate with `_gen_plural_rules.py` (needs `babel`); the check itself is dependency-free. |

The per-locale auditor subagent is `.claude/agents/translation-audit-locale.md`
(Read+Write only, **Opus** — it must out-class the model that produced the translations; Opus-made
demo content is the exception, see the localization spec §Models are pinned deliberately).

`consistency_check.py` is the deterministic complement to the LLM `consistency` finding: it catches
exact divergences for free; the auditor catches subtler synonym/inflection drift against the glossary
(`i18n/glossary.json`, injected into the audit prompt as a `{GLOSSARY}` block).

## Running it

The `audit-translations` skill owns the step-by-step flow: extract, dispatch, fan out one
`translation-audit-locale` agent per locale, report, and hand the flagged subset to
re-translation with `audit_report.py --write-manifest`.

## Findings shape

Each `tmp/translate-audit-outputs/{locale}.json` is:

```json
{
  "findings": [
    {
      "key": "...", "severity": "high|medium|low",
      "category": "<one of the categories in AUDIT_PROMPT_TEMPLATE.md>",
      "current": "<current translation>",
      "back_translation": "<literal English of current>",
      "issue": "<what's wrong>", "suggestion": "<improved translation>"
    }
  ],
  "locale_summary": "<1-2 sentence overall read>"
}
```

Clean strings are omitted. `audit_report.py` tags each finding `[llm]` (judged by the
auditor) or `[ratio]` (the deterministic length flag).

## Caveat: length ratio ≠ layout truth

The `[ratio]` length flag (`--max-expansion`, default 1.4; `--min-chars`, default 20 — short
strings have unstable ratios and rarely truncate, so they're skipped) catches translations
that are much longer than the English, but character count is only a **proxy** for whether a
string actually truncates — that depends on each control's width, which this pipeline has no budget
for. Treat `[ratio]` findings as "look at these," and rely on the auditor's `[llm]` length
judgment (justified vs. avoidable) for the verdict. True truncation is a UI-level check:
the localization spec §Large-type layout check.

Because of this, **`--write-manifest` excludes `[ratio]` findings** and re-translates only the
auditor's `[llm]`-judged subset. On German alone the ratio heuristic false-positives on standard
words (`Datenschutzerklärung`, `iCloud-Synchronisierung`); feeding those into the manifest would
re-translate correct strings and risk regressing them. Genuine length problems still reach the
manifest as `[llm]` `length` findings (each with a concrete tighter suggestion). `[ratio]` flags
remain in the human-readable report so you can eyeball them.

## Artifact layout (`tmp/`, gitignored)

```
tmp/
  translate-audit-inputs/audit_source.json     # audit_extract.py output
  translate-audit-prompts/{locale}.md          # audit_dispatch.py output
  translate-audit-outputs/{locale}.json        # subagent findings
  translate-inputs/{manifest,source}.json      # audit_report.py --write-manifest
```
