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
| `inspect_xcstrings.py` | Read-only catalog inspector (`info` / `find` / `show`) — use instead of ad-hoc `python3 -c` against the catalog |
| `inspect_glossary.py` | Read-only glossary inspector (`info` / `term`) — use instead of ad-hoc `python3 -c` against `glossary.json` |
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

`invalidate_keys.py` (force re-translation when the English source is unchanged):
- `--keys k1,k2,...` / `--keys-file PATH` — mark those keys' non-`en` locales `needs_review`
- Leaves the `en` source untouched; `extract.py --missing` then re-emits them
- Use when a glossary term was re-translated so every string embedding it must flow through
  translation again (the term-changed sibling of `update_keys.py`'s English-changed path)
- `--dry-run` — print what would be invalidated without writing

`inspect_xcstrings.py` (read-only; never reach for `python3 -c` on the catalog):
- `info` — sourceLanguage, key count, every locale present + per-locale string count
- `find SUBSTRING [--in key|value|both] [--case-sensitive]` — keys matching key name and/or
  English value; prints a trailing `COMMA LIST:` of keys to pipe into `--keys`/`--keys-file`
- `show KEY [KEY ...] [--locales a,b,c]` — value + state per locale for each key

`inspect_glossary.py` (read-only; never reach for `python3 -c` on `glossary.json`):
- `info [--kept-english]` — meta, protected terms, term list (`--kept-english` flags terms
  still carrying the English term verbatim in non-`en` locales)
- `term TERM [TERM ...] [--locales a,b,c]` — a term's translations across locales

```bash
# Which keys mention "carry-over" anywhere, and the resulting comma list:
python3 scripts/translate_catalog/inspect_xcstrings.py find carry-over
# A specific key's value+state in a few locales:
python3 scripts/translate_catalog/inspect_xcstrings.py show carryOver.label --locales de,fr,ja
# A glossary term's per-locale translations:
python3 scripts/translate_catalog/inspect_glossary.py term Carry-Over
```

## Catalog assumptions

- Keys with `"shouldTranslate": false` (locale-invariant identifiers) are skipped by `--missing`.
- Plural / device variations (`"variations"` blocks) are not yet handled in `--missing` subset mode.
  `check_translations.py` remains the authoritative gate and will catch any variation-shaped
  issues at pre-push time.

## Glossary (terminology consistency)

`glossary.json` pins **one canonical per-locale translation for recurring app terms** ("Add",
"Expense", "Budget", "Add Funds", …) so that two keys with the same English don't drift, and so a
compound like "Add Expense" reuses the agreed "Add" + "Expense". It is **consulted automatically**:
`dispatch_prompts.py` injects the relevant terms into each translation prompt as a `{GLOSSARY}` block
(rule 6 in `PROMPT_TEMPLATE.md` tells the model to use them but keep the full string coherent), and
`audit_dispatch.py` injects the same block so the auditor can raise `consistency` findings. Protected
nouns (Wren, iCloud) map to themselves.

Build / grow it with **Opus** agents (the `glossary-locale` agent, pinned to `model: opus`):

```bash
# Initial build (one-time):
python3 scripts/translate_catalog/glossary_build.py --candidates           # mine duplicate strings + frequent terms
python3 scripts/translate_catalog/glossary_build.py --write-curation-prompt # → tmp/glossary/curation_prompt.md
#   dispatch ONE glossary-locale (Opus) agent → tmp/glossary/terms.json (the curated term set)
python3 scripts/translate_catalog/glossary_build.py --dispatch              # → tmp/glossary/prompts/{locale}.md
#   fan out one glossary-locale (Opus) agent per locale → tmp/glossary/outputs/{locale}.json
python3 scripts/translate_catalog/glossary_build.py --merge                 # → glossary.json

# Grow it after new strings land (run from the translate-new-strings skill, step 4b):
python3 scripts/translate_catalog/glossary_sync.py --detect                 # high-confidence repeats → terms.json
#   then --dispatch / fan out / --merge for just the new terms (merge appends, never drops)
```

`glossary_sync.py --detect` auto-collects exact English strings now reused across ≥2 keys (the
high-confidence growth set) and writes ambiguous frequent words to `candidates_review.json` for a
human to skim. The deterministic divergence finder lives at
`scripts/translate_audit/consistency_check.py`.
