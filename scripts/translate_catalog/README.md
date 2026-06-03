# Translation pipeline

Translates `Localizable.xcstrings` from English into the 38 App Store storefront locales
using AI subagents (one per locale, dispatched in parallel by a parent agent).

The skill at `.claude/skills/translate-new-strings/` encodes the canonical workflow for
adding translations for newly-keyed strings; this README is the authority for *what each
script does*. The skill is the authority for *when and how to invoke them*.

> **Auditing existing translations for quality** (tone, register, cultural fit, length) is a
> separate pipeline: see `scripts/translate_audit/` (the `audit-translations` skill). It reads
> this folder's `locales.py` and `REGIONAL_NOTES`/`_GENERIC_NOTE`, grades the translations
> already in the catalog, and can emit a re-translation manifest that feeds back into the flow
> below.

## Scripts

| Script | Purpose |
|---|---|
| `locales.py` | Single source of truth: `LOCALES` list + `LOCALE_NAMES` map |
| `extract.py` | Read the catalog → write `tmp/translate-inputs/source.json` (and optionally `manifest.json`) |
| `dispatch_prompts.py` | Compose per-locale prompt files in `tmp/translate-prompts/` from `manifest.json` + `PROMPT_TEMPLATE.md` |
| `validate.py` | Validate `tmp/translate-outputs/{locale}.json` files against source |
| `merge.py` | Merge validated outputs back into `Localizable.xcstrings` |
| `PROMPT_TEMPLATE.md` | Template fed to per-locale subagents (placeholders substituted by `dispatch_prompts.py`) |

No dependencies beyond Python 3 stdlib.

## Default flow — adding/changing a small set of strings

Use this whenever you've added new `String(localized:)` / `LocalizedStringResource` keys
or Xcode has flagged existing keys as `stale` / `needs_review`.

```bash
# 1. Find what actually needs translating. Writes source.json AND manifest.json.
python3 scripts/translate_catalog/extract.py --missing

# 2. Compose ready-to-dispatch per-locale prompts.
python3 scripts/translate_catalog/dispatch_prompts.py

# 3. Parent agent: read each tmp/translate-prompts/{locale}.md and dispatch
#    one subagent per locale with that prompt. Subagents must write their
#    output JSON to tmp/translate-outputs/{locale}.json.

# 4. Validate the partial outputs (subset mode — only checks keys actually translated).
python3 scripts/translate_catalog/validate.py --subset

# 5. Merge into the catalog.
python3 scripts/translate_catalog/merge.py

# 6. Authoritative pre-push gate — must exit 0 before the work is done.
python3 scripts/check_translations.py
python3 scripts/check_source_strings.py

# 7. Build + test
make format && make lint-fix && make build && make test
```

`check_translations.py` is the same script lefthook runs on pre-push (see `lefthook.yml`),
so a clean exit here means the push will pass that gate.

## Full backfill — regenerate every locale from scratch

Only needed when changing the model, fixing a systemic prompt issue, or seeding a new
catalog from scratch. Costs O(38 × all-keys).

```bash
python3 scripts/translate_catalog/extract.py                     # all keys, no manifest
# Manually fan out subagents using PROMPT_TEMPLATE.md, one per locale, full source.json
python3 scripts/translate_catalog/validate.py                    # strict — full source required
python3 scripts/translate_catalog/merge.py
python3 scripts/check_translations.py
make format && make lint-fix && make build && make test
```

## Script flags reference

`extract.py`:
- (no flags) — emit every translatable key
- `--keys k1,k2,...` — emit only those keys
- `--keys-file PATH` — keys from a file, one per line
- `--missing` — emit only keys missing/stale in any locale; also writes `manifest.json`

`validate.py`:
- `--subset` — only check keys present in each output file (partial-translation mode)
- positional locale args — restrict to those locales

`merge.py`:
- `--keys k1,k2,...` / `--keys-file PATH` — only merge those keys, ignore others
- positional locale args — restrict to those locales
- Refuses to overwrite a catalog entry with an empty/non-string value (existing translation preserved)

## Catalog assumptions

- Keys with `"shouldTranslate": false` (locale-invariant identifiers) are skipped by `--missing`.
- Plural / device variations (`"variations"` blocks) are not yet handled in `--missing` subset mode.
  `check_translations.py` remains the authoritative gate and will catch any variation-shaped
  issues at pre-push time.
