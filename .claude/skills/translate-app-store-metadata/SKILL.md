---
name: translate-app-store-metadata
description: Transcreate the App Store listing (name, subtitle, keywords, promotional text, description, release notes) from English into all 38 App Store storefront locales under fastlane/metadata/. Use after editing any fastlane/metadata/en-US/*.txt, or when check_metadata.py reports gaps. Drives the scripts/translate_metadata/ pipeline in subset mode with parallel per-storefront Opus subagents. This is the App-Store-metadata sibling of translate-new-strings (which handles in-app strings).
---

# Translate App Store metadata

Canonical recipe for getting `fastlane/metadata/` to a fully-transcreated state
after authoring or editing the English (`en-US`) listing copy. Drives the
existing `scripts/translate_metadata/` pipeline in subset mode.

**Definition of done:** `python3 scripts/translate_metadata/check_metadata.py`
exits 0 — every translatable field the English source has authored is populated
and within its character limit across all 38 target storefronts.

This is the **metadata** pipeline (App Store listing). For in-app UI strings in
`Localizable.xcstrings`, use the separate `translate-new-strings` skill. They use
different locale code systems (storefront vs runtime); `metadata_locales.py` owns
the mapping.

## Hard rules

- **Never write ad-hoc Python** (`python3 -c`, throwaway `tmp/*.py`) to slice the
  source, filter outputs, or post-process metadata. Every operation has a flag on
  one of the existing `scripts/translate_metadata/` scripts. If you reach for
  inline Python, **stop** — extend a script instead so the permission surface
  stays narrow.
- **Never skip the gate.** Treat anything less than `exit 0` from
  `check_metadata.py` as not-done and loop back.
- **The brand "Wren" stays verbatim** in every locale — never translated,
  transliterated, or glossed. (This is enforced by the prompt and validated by
  `validate.py`; do not "remind" subagents in the dispatch message — fix
  `PROMPT_TEMPLATE.md` if a rule needs strengthening.)
- **All commands run from the repo root.**

## Prerequisite: English source copy must exist

The pipeline transcreates whatever non-empty translatable fields exist in
`fastlane/metadata/en-US/`. Before translating, confirm these are authored:
`name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`,
`promotional_text.txt`, `release_notes.txt`. If a field is intentionally blank
(e.g. no promotional text this release), the pipeline simply skips it.

## Recipe

### 1. Detect what needs transcreating

```bash
python3 scripts/translate_metadata/extract.py --missing
```

Writes:
- `tmp/metadata-inputs/source.json` — every authored en-US field with its value
  and character limit.
- `tmp/metadata-inputs/manifest.json` — `{storefront: [fields...]}` listing the
  gaps to fill.

If the manifest is empty, skip to step 5 to confirm.

### 2. Compose per-storefront prompts

```bash
python3 scripts/translate_metadata/dispatch_prompts.py
```

Writes one ready-to-dispatch prompt per storefront to
`tmp/metadata-prompts/{storefront}.md`, with `{LOCALE_NAME}`, `{LOCALE_CODE}`,
`{CULTURAL_NOTE}`, `{BRAND}`, and `{SOURCE_JSON}` (sliced to that storefront's
gaps, annotated with char limits and per-field guidance) substituted. Also clears
stale output files for those storefronts.

### 3. Dispatch one `metadata-locale` subagent per storefront, in parallel

For every `tmp/metadata-prompts/{storefront}.md` that exists, invoke an `Agent`:

- `subagent_type`: `metadata-locale` (defined in `.claude/agents/metadata-locale.md`,
  Read+Write only, model **opus**).
- A short dispatch prompt naming the input and output paths. Example:
  > Read `/abs/path/tmp/metadata-prompts/de-DE.md` and follow the rules in it.
  > Write the resulting JSON object (nothing else) to
  > `/abs/path/tmp/metadata-outputs/de-DE.json`.

**Send all subagent calls in a single message** so they run concurrently. Do not
pass `subagent_type: general-purpose` — the narrow agent is what keeps the
dispatches auto-approvable in `.claude/settings.json`.

The prompt file already contains every rule (brand, char limits, keywords-as-search,
tone/register, JSON-only). Do not modify it in the dispatch message.

### 4. Validate, then merge

```bash
python3 scripts/translate_metadata/validate.py --subset
```

`--subset` checks only the fields present in each output file. Most common
failures and fixes:
- **Over the character limit** (especially `name`/`subtitle` at 30) — re-dispatch
  that storefront; the prompt tells the model to tighten until it fits.
- **`name` missing the brand prefix** — re-dispatch.
- **Keyword hygiene warnings** (spaces after commas, dupes) are warnings, not
  failures, but re-dispatch if egregious.

Once `validate.py --subset` exits 0:

```bash
python3 scripts/translate_metadata/merge.py
```

Writes each field to `fastlane/metadata/{storefront}/{field}.txt` and copies the
URL files verbatim from en-US. Refuses to clobber a non-empty file with an empty
value.

### 5. Authoritative gate

```bash
python3 scripts/translate_metadata/check_metadata.py
```

This walks `fastlane/metadata/` directly (not the tmp/ intermediates), so it
catches anything that didn't merge. If it reports gaps, loop back to step 1
(`extract.py --missing` will re-flag exactly what's left).

### 6. Ship (when ready)

Upload metadata only (no binary), or include in a full release:

```bash
fastlane push_metadata
# or flip skip_metadata:false in the `release` lane and run `fastlane release`
```

`push_metadata` / `release` touch App Store Connect — only run them when you
actually intend to upload. See `fastlane/SETUP.md`.

## When NOT to use this skill

- Editing in-app UI strings → use `translate-new-strings`.
- Capturing localized screenshots → out of scope (separate `fastlane screenshots`
  flow, not built yet).
