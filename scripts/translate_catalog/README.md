# Translation pipeline

Translates `Localizable.xcstrings` from English into the 49 App Store storefront locales
using AI subagents (one per locale, dispatched in parallel by a parent agent).

This README is the authority for *what each script does*; the `translate-new-strings` skill
is the authority for *when and how to invoke them*, and owns the step-by-step flow.

> **Auditing existing translations for quality** (tone, register, cultural fit, length) is a
> separate pipeline: see `scripts/translate_audit/` (the `audit-translations` skill). It reads
> this folder's `locales.py` and the in-app notes (`i18n/regional_notes.json`), grades the translations
> already in the catalog, and can emit a re-translation manifest that feeds back into this one.

## Scripts

| Script | Purpose |
|---|---|
| `locales.py` | `LOCALES`, `LOCALE_NAMES`, runtime↔storefront maps — derived from the registry in `fastlane/screenshot-config.json` |
| `app_config.py` | This app's data from `i18n/`: brand, protected terms, paths, notes, brief fragments, allowlists |
| `paths.py` | `CATALOG_PATH`, `SOURCE_DIR`, `SEEDS_DIR` (from `i18n/app.json`) |
| `extract.py` | Read the catalog → write `tmp/translate-inputs/source.json` (and, with `--missing`, `manifest.json`) |
| `dispatch_prompts.py` | Compose per-locale prompt files in `tmp/translate-prompts/` from `manifest.json` + the prompt templates |
| `validate.py` | Validate `tmp/translate-outputs/{locale}.json` and `{locale}.sample.json` against source |
| `merge.py` | Merge validated outputs back into `Localizable.xcstrings` |
| `add_keys.py` / `update_keys.py` / `remove_keys.py` / `rename_keys.py` / `pluralize_keys.py` / `invalidate_keys.py` | Catalog key maintenance; each script's docstring gives its input shape |
| `sync_catalog.py` | Merge the last `make build`'s extracted strings into the catalog as a build in Xcode does (`make i18n-sync`); `--check` is the gate's `make i18n-sync-check` |
| `xcstrings_io.py` | The one catalog writer, in Xcode's exact bytes |
| `glossary_build.py` / `glossary_sync.py` | Build and grow `i18n/glossary.json` (below) |
| `inspect_xcstrings.py` | Read-only catalog inspector (`info` / `find` / `show`) — use instead of ad-hoc `python3 -c` against the catalog |
| `inspect_glossary.py` | Read-only glossary inspector (`info` / `term`) — use instead of ad-hoc `python3 -c` against `glossary.json` |
| `PROMPT_TEMPLATE.md` | UI-key template → `{locale}.md`, for the `translation-locale` agent |
| `SAMPLE_PROMPT_TEMPLATE.md` | Demo-content template (keys under i18n/app.json `transcreatedNamespaces`) → `{locale}.sample.md`, for the `sample-content-locale` agent (transcreated for cultural fit, structure fixed) |

No dependencies beyond Python 3 stdlib.

App-specific text never lives in this folder: the templates take their app prose from
`i18n/brief.md`, and the per-locale notes live in `i18n/regional_notes.json` (in-app) and
`i18n/cultural_notes.json` (store), kept apart on purpose. The locale registry's `register` field
holds the formality call; every prompt states it on its own line, so the notes never do.

## Full backfill

`dispatch_prompts.py` needs the `manifest.json` that only `extract.py --missing` writes. To
regenerate every locale (a systemic prompt or rule change, or recovery; never a model or alias
bump on its own: the localization spec §Models are pinned deliberately), mark the keys
`needs_review` with `invalidate_keys.py` (optionally `--locales`), then run the normal flow.
Costs O(49 × all-keys).

## Script flags reference

`extract.py`:
- (no flags) — emit every translatable key
- `--keys k1,k2,...` — emit only those keys
- `--keys-file PATH` — keys from a file, one per line
- `--missing` — emit only keys missing/stale in any locale, plurals included; also writes `manifest.json`

`validate.py`:
- `--subset` — only check keys present in each output file (partial-translation mode)
- positional locale args — restrict to those locales

`merge.py`:
- `--keys k1,k2,...` / `--keys-file PATH` — only merge those keys, ignore others
- positional locale args — restrict to those locales
- Refuses to overwrite a catalog entry with an empty/non-string value (existing translation preserved)

`invalidate_keys.py` (force re-translation when the English source is unchanged):
- `--keys k1,k2,...` / `--keys-file PATH` — mark those keys' non-`en` locales `needs_review`
- `--locales a,b,c` — invalidate only those locales (default: every non-`en` locale)
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
# Which keys mention "reset" anywhere, and the resulting comma list:
python3 scripts/translate_catalog/inspect_xcstrings.py find reset
# A specific key's value+state in a few locales:
python3 scripts/translate_catalog/inspect_xcstrings.py show common.action.cancel --locales de,fr,ja
# A glossary term's per-locale translations:
python3 scripts/translate_catalog/inspect_glossary.py term "Reset All"
```

## Catalog assumptions

- Keys with `"shouldTranslate": false` (locale-invariant identifiers) are skipped by `--missing`.

## Glossary (terminology consistency)

`i18n/glossary.json` pins **one canonical per-locale translation for recurring app terms** so that
two keys with the same English don't drift, and so a compound reuses the agreed translation of its
parts. It is **consulted automatically**:
`dispatch_prompts.py` injects the relevant terms into each translation prompt as a `{GLOSSARY}` block
(the template tells the model to use them but keep the full string coherent), and
`audit_dispatch.py` injects the same block so the auditor can raise `consistency` findings. Protected
nouns (i18n/app.json `protected`) map to themselves.

Build / grow it with **Opus** agents (the `glossary-locale` agent, pinned to `model: opus`):

```bash
# Initial build (one-time):
python3 scripts/translate_catalog/glossary_build.py --candidates           # mine duplicate strings + frequent terms
python3 scripts/translate_catalog/glossary_build.py --write-curation-prompt # → tmp/glossary/curation_prompt.md
#   dispatch ONE glossary-locale (Opus) agent → tmp/glossary/terms.json (the curated term set)
python3 scripts/translate_catalog/glossary_build.py --dispatch              # → tmp/glossary/prompts/{locale}.md
#   fan out one glossary-locale (Opus) agent per locale → tmp/glossary/outputs/{locale}.json
python3 scripts/translate_catalog/glossary_build.py --merge                 # → i18n/glossary.json

# Grow it after new strings land:
python3 scripts/translate_catalog/glossary_sync.py --detect                 # high-confidence repeats → terms.json
#   then --dispatch / fan out / --merge for just the new terms (merge appends, never drops)
```

`glossary_sync.py --detect` auto-collects exact English strings now reused across ≥2 keys (the
high-confidence growth set) and writes ambiguous frequent words to `candidates_review.json` for a
human to skim. The deterministic divergence finder lives at
`scripts/translate_audit/consistency_check.py`.
