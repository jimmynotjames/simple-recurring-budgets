# `translate_metadata/` — App Store listing transcreation pipeline

Fills `fastlane/metadata/<storefront>/*.txt` for all 38 target App Store
storefronts by transcreating the English (`en-US`) listing copy. This is the
App-Store-metadata sibling of `scripts/translate_catalog/` (which handles in-app
`Localizable.xcstrings`).

The two pipelines are deliberately separate because they use **different locale
code systems**:

| Pipeline | Codes | Source of truth |
|----------|-------|-----------------|
| `translate_catalog/` (in-app UI) | runtime BCP 47 (`de`, `nb`, `nl`, `ar`) | `Localizable.xcstrings` |
| `translate_metadata/` (this one)  | ASC storefront (`de-DE`, `no`, `nl-NL`, `ar-SA`) | `fastlane/metadata/en-US/` |

`metadata_locales.py` owns the `runtime → storefront` mapping so the two stay in lockstep.

## What it translates

Transcreated per storefront (with App Store Connect character limits):

| Field | Limit | Notes |
|-------|-------|-------|
| `name` | 30 | Must start with the brand **Wren**; only the descriptor is localized. |
| `subtitle` | 30 | Punchy tagline. |
| `promotional_text` | 170 | Editable without a new app version. |
| `keywords` | 100 | **Search terms**, not prose — comma-separated, no spaces, deduped. |
| `description` | 4000 | Full persuasive listing copy; structure preserved. |
| `release_notes` | 4000 | "What's New" text. |

Copied verbatim from `en-US` by `merge.py` (never sent to the model):
`marketing_url`, `privacy_url`, `support_url`. The catalog-level
`copyright.txt` is left untouched.

The brand **"Wren"** is treated as a proper noun everywhere: never translated,
transliterated, or glossed. (Decision: brand stays Latin in all locales — no
localized home-screen icon name / `InfoPlist.xcstrings` is required.)

## The recipe (driven by the `translate-app-store-metadata` skill)

All commands run from the repo root.

```bash
# 1. Extract the English source + the list of per-storefront gaps to fill.
python3 scripts/translate_metadata/extract.py --missing

# 2. Compose one transcreation prompt per storefront (sliced to its gaps).
python3 scripts/translate_metadata/dispatch_prompts.py

# 3. Fan out one `metadata-locale` subagent (Opus) per storefront, in parallel.
#    Each reads tmp/metadata-prompts/{storefront}.md and writes
#    tmp/metadata-outputs/{storefront}.json. (The skill drives this step.)

# 4. Validate (char limits, brand prefix, keyword format, ...) then merge.
python3 scripts/translate_metadata/validate.py --subset
python3 scripts/translate_metadata/merge.py

# 5. Authoritative gate — walks fastlane/metadata/ directly.
python3 scripts/translate_metadata/check_metadata.py
```

`check_metadata.py` exiting 0 is the definition of done.

## Files

```
scripts/translate_metadata/
  metadata_locales.py   # storefront list, runtime→storefront map, field limits, brand, names
  extract.py            # en-US/*.txt → tmp/metadata-inputs/source.json (+ --missing → manifest.json)
  dispatch_prompts.py   # source + manifest + PROMPT_TEMPLATE.md → tmp/metadata-prompts/{storefront}.md
  validate.py           # --subset; char limits, brand prefix, keyword hygiene, non-empty
  merge.py              # tmp/metadata-outputs/{storefront}.json → fastlane/metadata/{storefront}/*.txt + URL passthrough
  check_metadata.py     # authoritative gate over fastlane/metadata/
  PROMPT_TEMPLATE.md    # transcreation prompt template
  README.md             # this file

.claude/agents/
  metadata-locale.md    # subagent (Read+Write, model: opus) used by step 3

tmp/
  metadata-inputs/source.json
  metadata-inputs/manifest.json
  metadata-prompts/{storefront}.md
  metadata-outputs/{storefront}.json
```

## Shipping the result

Once `check_metadata.py` is green, upload metadata-only with the dormant lane:

```bash
fastlane push_metadata
```

or include it in a full release by flipping `skip_metadata: true → false` in the
`release` lane of `fastlane/Fastfile`. See `fastlane/SETUP.md`.

## Re-running after an English copy edit

Edit the relevant `fastlane/metadata/en-US/*.txt`, then re-run the recipe. To
force a full re-transcreation of a field across all storefronts (e.g. you
rewrote the description), delete that field's `.txt` in the target folders first,
or just delete the target folders and let `extract.py --missing` flag everything.
