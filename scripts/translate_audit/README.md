# Translation audit pipeline

Audits the **existing** non-English translations in
`simple-recurring-budgets/Resources/Localizable.xcstrings` for **quality** — tone, formality
register, cultural appropriateness, length/truncation risk, and accuracy — and produces a
triage report plus a re-translation manifest for the strings that need fixing.

This is the quality-audit sibling of `scripts/translate_catalog/` (which *creates* and
*structurally validates* translations). The two are deliberately separate:

- `scripts/translate_catalog/` = produce + structurally gate translations (the
  `translate-new-strings` skill).
- `scripts/translate_audit/` (this folder) = grade the translations already in the catalog
  (the `audit-translations` skill).

It **reuses** the catalog pipeline's single sources of truth via import — `locales.py`
(`LOCALES`, `LOCALE_NAMES`) and `dispatch_prompts.py` (`REGIONAL_NOTES`, `_GENERIC_NOTE`,
the per-locale register/cultural notes) — so the auditor grades against the same per-locale
rubric the translator was given. Nothing here is duplicated from there. Python 3 stdlib only.

The full design and status live in `docs/audits/translation-quality-audit-2026-06-02.md`.

## Scripts

| Script | Purpose |
|---|---|
| `audit_extract.py` | Read the catalog → write `tmp/translate-audit-inputs/audit_source.json` (English source + comment + format specifiers + **every locale's current translation**). |
| `AUDIT_PROMPT_TEMPLATE.md` | Per-locale auditor prompt template (placeholders substituted by `audit_dispatch.py`): the tone/register/length/accuracy rubric + the locale's regional note + the source block. |
| `audit_dispatch.py` | Compose ready-to-dispatch per-locale audit prompts in `tmp/translate-audit-prompts/{locale}.md`. |
| `audit_report.py` | Aggregate the per-locale findings into a triage report; deterministic length pre-filter; `--write-manifest` to feed the re-translation step. |

The per-locale auditor subagent is `.claude/agents/translation-audit-locale.md`
(Read+Write only, **Opus** — it must out-class the model that produced the translations).

## Flow

```bash
# 1. Pull English + all current translations out of the catalog.
python3 scripts/translate_audit/audit_extract.py            # all keys, all locales
#   (or:  audit_extract.py de ja   /   audit_extract.py --keys k1,k2)

# 2. Compose one audit prompt per locale.
python3 scripts/translate_audit/audit_dispatch.py           # all locales with translations

# 3. Parent agent: for each tmp/translate-audit-prompts/{locale}.md, dispatch one
#    `translation-audit-locale` subagent (in parallel, single message) that reads that
#    prompt and writes findings to tmp/translate-audit-outputs/{locale}.json.

# 4. Aggregate into a triage report.
python3 scripts/translate_audit/audit_report.py             # everything
python3 scripts/translate_audit/audit_report.py --min-severity medium

# 5. Emit a re-translation manifest for the flagged subset (Track C hand-off).
python3 scripts/translate_audit/audit_report.py --write-manifest --min-severity medium
#   → writes tmp/translate-inputs/{manifest,source}.json in the shape extract.py --missing
#     produces, so the translate-new-strings flow re-translates exactly those (key,locale)
#     pairs — re-translate with a stronger model for this round.
```

Recommended: dry-run a single locale end-to-end first (`audit_extract.py de` →
`audit_dispatch.py de` → one subagent → `audit_report.py de`) and sanity-check the findings
before fanning out to all 38.

## Findings shape

Each `tmp/translate-audit-outputs/{locale}.json` is:

```json
{
  "findings": [
    {
      "key": "...", "severity": "high|medium|low",
      "category": "tone|register|cultural|accuracy|grammar|length",
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
judgment (justified vs. avoidable) for the verdict. True truncation is a UI-level check; see
the audit doc's "Layout truncation" section.

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
  translate-inputs/{manifest,source}.json      # audit_report.py --write-manifest (Track C hand-off)
```
