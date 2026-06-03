---
name: translate-new-strings
description: Translate newly-added or stale keys in Localizable.xcstrings to all 38 App Store storefront locales. Use after adding any LocalizedStringResource / String(localized:) / Text("…") key, or when check_translations.py reports issues. Drives the scripts/translate_catalog/ pipeline in subset mode with parallel per-locale subagents.
---

# Translate new strings

Canonical recipe for getting `Localizable.xcstrings` back to a fully-translated state
after adding, changing, or invalidating keys. This skill drives the existing
`scripts/translate_catalog/` pipeline in subset mode.

**Definition of done:** `python3 scripts/check_translations.py` exits 0. That is the same
check `lefthook.yml` runs on `pre-push`, so a clean exit here guarantees the push will
pass the translation gate.

## Hard rules

- **Never write ad-hoc Python** (`python3 -c "..."` heredocs, throwaway `tmp/*.py`)
  to slice `source.json`, filter outputs, add catalog keys, remove catalog keys, or
  post-process anything. Every operation in this pipeline has a flag on one of the
  existing scripts. If you find yourself reaching for `python3 -c`, **stop** — the
  right move is to extend one of the existing scripts (or add a new primitive to
  `scripts/translate_catalog/`) so the workflow stays disciplined and the permission
  surface stays narrow. Treat the urge to write inline Python as a signal that this
  skill is missing a primitive.
  - **Adding keys → `add_keys.py`** (see Step 0a)
  - **Updating English source text → `update_keys.py`** (see Step 0b)
  - **Renaming keys → `rename_keys.py`** (see Step 0c)
- **Never skip the pre-push checks** at the end. Treat anything less than `exit 0` from
  `check_translations.py` as not-done and loop back.
- **All commands run from repo root.** Paths in this skill are repo-relative.

## Recipe

### 0. Catalog maintenance (before translating)

Run whichever of these applies before Step 1. All three scripts are pre-approved in
`.claude/settings.json` and will not prompt. **Do not use inline Python for any of
these operations.**

Both invocation forms shown below work without prompting: the heredoc form (no temp
file, preferred for small batches) and the temp-file form (useful for large batches).
For the temp-file form, write JSON to `tmp/<anything>.json` — the `Write(tmp/**)` and
`Bash(python3 scripts/translate_catalog/<script>:*)` permissions are both pre-approved.

---

#### 0a. Add new keys

Use when `String(localized: "key.name")` exists in Swift but the key is not yet in
`Localizable.xcstrings`. Inserts the key with `en.state: translated`; leaves all other
locales absent so `extract.py --missing` flags them automatically.

```bash
python3 scripts/translate_catalog/add_keys.py - << 'EOF'
{
  "my.feature.title": {
    "comment": "Title shown on the My Feature screen",
    "value": "My Feature"
  }
}
EOF
```

Input shape: `{ "key": { "comment": "...", "value": "English string" } }`.
Existing keys are skipped unless `--force` is passed.

---

#### 0b. Update English source text

Use when the displayed English text for an existing key changes (copy edit, wording
change, etc.). Updates the `en` value and marks every existing non-`en` translation
`needs_review` so the full re-translation round-trip runs automatically via Step 1.

```bash
python3 scripts/translate_catalog/update_keys.py - << 'EOF'
{
  "my.feature.title": {
    "value": "Revised English text",
    "comment": "Updated hint (optional — omit to keep existing comment)"
  }
}
EOF
```

Input shape: `{ "key": { "value": "New English string", "comment": "..." } }`.
`comment` is optional. Keys absent from the catalog are skipped with a warning.

---

#### 0c. Rename keys

Use when a key identifier changes (e.g. a UI element moved to a different screen or
section and the key path should reflect that) but the displayed text and all translations
stay exactly the same. Copies the full entry — comment, `extractionState`, every locale
translation — from the old key to the new key, then removes the old key. **No
re-translation is needed after a pure rename.**

```bash
python3 scripts/translate_catalog/rename_keys.py - << 'EOF'
{
  "old.screen.featureName": "new.screen.featureName"
}
EOF
```

Input shape: `{ "old.key": "new.key" }`. Supports `--dry-run` to preview changes
and `--force` to overwrite an existing new key.

After renaming, update the Swift call sites to use the new key, then run
`check_source_strings.py` (Step 5) to confirm no stale references remain. No need to
run `extract.py --missing` unless you also changed the English text.

#### 0d. Convert count strings to plurals

Use when a string interpolates a count (`%lld`) and reads wrong at 1 (e.g. "1 logged
expenses"). Converts the key's English to a CLDR `variations.plural` block and clears the
non-en locales so they re-translate as plurals (each locale gets the categories *it* needs).

```bash
python3 scripts/translate_catalog/pluralize_keys.py - << 'EOF'
{ "my.count.key": { "one": "%lld item", "other": "%lld items" } }
EOF
```

`other` is required. Then run Step 1 onward — the pipeline emits/validates/merges plural keys
end to end (subagents return a `{ "key": {"one": …, "other": …} }` object for plural keys per
rule 7 in the template). The pre-push gate (`check_translations.py`) already validates plural
variations.

### 1. Detect what needs translating

```bash
python3 scripts/translate_catalog/extract.py --missing
```

This writes:
- `tmp/translate-inputs/source.json` — the union of all keys that are missing or stale
  in at least one locale, with English source + comment + format specifiers.
- `tmp/translate-inputs/manifest.json` — `{locale: [keys...]}` telling you exactly which
  locales need work and for which keys.

If the script reports "No missing or stale translations found", you are done — skip to
step 5 to confirm.

### 2. Compose per-locale prompts

```bash
python3 scripts/translate_catalog/dispatch_prompts.py
```

This writes one ready-to-dispatch prompt per locale to
`tmp/translate-prompts/{locale}.md`. Each prompt has `{LOCALE_NAME}`, `{LOCALE_CODE}`,
`{REGIONAL_NOTE}`, `{GLOSSARY}`, and `{SOURCE_JSON}` (sliced to just that locale's missing keys)
already substituted.

`{GLOSSARY}` is filled automatically from `scripts/translate_catalog/glossary.json`: for each
locale, `dispatch_prompts.py` injects the agreed translations of any glossary term that appears in
that slice, so new strings stay terminologically consistent with the rest of the app (rule 6 in the
template tells the subagent how to use them, including for sub-parts of a string). Nothing to do
here — it just works when the glossary is populated.

By default this also deletes any stale `tmp/translate-outputs/{locale}.json` files
for the locales in the manifest, so step 3's subagents start from a clean slate and
step 4's `validate.py --subset` doesn't trip on leftover keys from a prior run on a
different branch. Pass `--no-clean` only if you're manually iterating on one locale's
output and want to preserve the others.

### 3. Translate each locale's slice

> **Cross-tool execution.** On **Claude Code**, dispatch one `translation-locale` subagent per locale
> in parallel (below). On **Cursor** or any tool without a subagent primitive, run the same step
> **inline and serially**: for each `tmp/translate-prompts/{locale}.md`, read it, produce the
> translation JSON yourself, and write `tmp/translate-outputs/{locale}.json` — then continue to
> step 4. Same scripts, same gates, same result. Canonical: `AGENTS.md > Cross-cutting concerns >
> Running the translation pipelines`.

#### Claude Code — one `translation-locale` subagent per locale, in parallel

For every `tmp/translate-prompts/{locale}.md` that exists, invoke an `Agent` with:

- `subagent_type`: `translation-locale` (defined in `.claude/agents/translation-locale.md`)
- A short dispatch prompt that tells the subagent which prompt file to read and where
  to write its JSON output. Example:
  > Read `/abs/path/tmp/translate-prompts/ja.md` and follow the rules in it. Write the
  > resulting JSON object (nothing else) to `/abs/path/tmp/translate-outputs/ja.json`.

The subagent definition restricts the subagent to `Read` + `Write` only, defaults to
`haiku`, and encodes the "JSON only, this file only" contract. Do not pass
`subagent_type: general-purpose` — the narrower agent is what makes the dispatches
auto-approvable in this project's `.claude/settings.json`.

**Send all subagent calls in a single message** so they run concurrently. With 38
locales × small key counts this typically finishes in well under a minute.

The subagent's prompt already contains every translation rule — placeholder preservation,
tone, regional dialect notes, JSON-only output. Do not modify it.

### 4. Validate, then merge

```bash
python3 scripts/translate_catalog/validate.py --subset
```

`--subset` mode only checks the keys actually present in each output file (the manifest
slice), so partial outputs are first-class. If any locale fails:

- Re-read its prompt, re-dispatch a fresh subagent (often the same prompt works on
  retry), then re-validate.
- Format-specifier mismatches are the most common failure — the subagent's translation
  dropped or duplicated a `%@` / `%lld`. Retry usually fixes it.

Once `validate.py --subset` exits 0:

```bash
python3 scripts/translate_catalog/merge.py
```

Merge only writes catalog entries for keys present in the output files, and refuses to
overwrite a non-empty entry with an empty value, so existing translations are safe.
For each key it merges, `merge.py` also promotes that key's English source from
`state: "new"` → `"translated"` (Xcode auto-extraction lands new keys as `"new"`). This
means a key that went through this pipeline will **not** trip the `NEW [en] (source)`
gate in step 5 — the previous manual `add_keys.py --force` + re-merge dance is no longer
needed for pipeline keys.

**Fast path — steps 4 and 5 in one shot.** Once the subagents have written
`tmp/translate-outputs/`, run the deterministic tail as a single command (every
sub-command is individually allowlisted, so it never prompts):

```bash
python3 scripts/translate_catalog/validate.py --subset \
  && python3 scripts/translate_catalog/merge.py \
  && python3 scripts/check_translations.py \
  && python3 scripts/check_source_strings.py
```

If `validate.py --subset` fails for a locale, re-dispatch that locale's subagent and
re-run the chain. Don't split these into four separate tool calls — that's slower and
was the source of past friction.

### 4b. Keep the glossary current (after merge)

New features often introduce terminology that now recurs across keys. Keep the glossary
(`scripts/translate_catalog/glossary.json`) in step with it:

```bash
python3 scripts/translate_catalog/glossary_sync.py --detect
```

This is deterministic (no LLM). It detects **high-confidence** new terms — an English string now
reused across ≥2 keys but not yet in the glossary — and writes them to `tmp/glossary/terms.json`;
more ambiguous frequent words go to `tmp/glossary/candidates_review.json` for you to skim. If it
reports new high-confidence terms, add them to the glossary (Opus):

```bash
python3 scripts/translate_catalog/glossary_build.py --dispatch
# fan out one glossary-locale (Opus) agent per tmp/glossary/prompts/{locale}.md, in a single
# message; each writes tmp/glossary/outputs/{locale}.json (see the audit/glossary docs)
python3 scripts/translate_catalog/glossary_build.py --merge
```

`--merge` appends to `glossary.json` (it never drops existing terms). Skip this step entirely if
`--detect` reports nothing new. The fuller glossary build/rebuild flow lives in
`scripts/translate_catalog/README.md`.

### 5. Authoritative pre-push gate

```bash
python3 scripts/check_translations.py
python3 scripts/check_source_strings.py
```

Both are run by `lefthook.yml` on `pre-push`.

- `check_translations.py` is the **definition of done** for this skill. It walks the
  catalog (not the per-locale output files), so it catches anything that didn't actually
  merge in correctly. If it reports missing/stale `(key, locale)` pairs:
  - Run `extract.py --keys k1,k2,...` for just those keys, or re-run `--missing`.
  - Loop back to step 2.
- `check_source_strings.py` catches hard-coded `Text("English string")` in Swift files.
  A failure here means there's an un-keyed string in production code — fix that first
  (add to xcstrings, then re-run this skill), since untranslated keys are downstream of
  un-keyed strings.
- `NEW [en] '<key>' (source)` means the key's English source state is still `"new"`
  (Xcode-extracted, not yet reviewed). For keys you just translated this is now
  auto-resolved by `merge.py` (see step 4). It can still surface for a key whose 38
  locales were *already* complete (so nothing merged) but whose en stayed `"new"` — in
  that rare case run `extract.py --keys <key>` then the step-4 fast-path chain, or
  re-run `merge.py` (the existing `tmp/translate-outputs/<locale>.json` are reused and
  the en promotion fires). Do not hand-edit the catalog.

If `check_translations.py` reports keys that exist in the catalog but no longer have a
Swift reference (i.e. the code dropped the `String(localized: ...)` call), those keys
are **orphaned**. Remove them with:

```bash
python3 scripts/translate_catalog/remove_keys.py --keys k1,k2,...
# or
python3 scripts/translate_catalog/remove_keys.py --keys-file path/to/keys.txt
```

This deletes every locale entry for those keys cleanly. Use `--dry-run` first to see
what would be removed.

### 6. Build + test

Standard four-step from `AGENTS.md`:

```bash
make format && make lint-fix && make build && make test
```

## Subagent prompt invariants

The prompt file generated by `dispatch_prompts.py` is the single source of truth.
Subagents are told to:

1. Preserve every format specifier exactly (count and form; order may change for grammar).
2. Use the `comment` field for context.
3. Match Apple's first-party iOS app voice for the target locale.
4. Leave `iCloud`, `Carry-Over`, and other Apple-untranslated proper nouns in English.
5. Output only the JSON object — no markdown fences, no prose.

If you find yourself wanting to "remind" the subagent of one of these rules in the
dispatch message, instead **fix `PROMPT_TEMPLATE.md`** so the rule survives across runs.

## When to fall back to full backfill

This skill is the right tool when keys have been added/changed for a feature. It is
**not** the right tool when:

- Changing the translation model and wanting to regenerate every existing translation.
- Seeding a brand-new catalog from scratch.
- Recovering from a corrupted catalog.

For those, see "Full backfill" in `scripts/translate_catalog/README.md`.

## File layout reference

```
scripts/translate_catalog/
  locales.py            # LOCALES list + LOCALE_NAMES
  add_keys.py           # Step 0a: register new en keys; JSON file or stdin
  update_keys.py        # Step 0b: update en source text + invalidate translations; JSON file or stdin
  rename_keys.py        # Step 0c: rename keys preserving all translations; --dry-run; JSON file or stdin
  extract.py            # --missing | --keys | --keys-file | (no flags = all)
  dispatch_prompts.py   # manifest + template → tmp/translate-prompts/; cleans stale outputs by default
  validate.py           # --subset for partial outputs
  merge.py              # --keys filter; rejects empty values
  remove_keys.py        # --keys | --keys-file; deletes orphaned keys with all locale entries
  PROMPT_TEMPLATE.md    # subagent prompt template
  README.md             # script reference

scripts/
  check_translations.py    # authoritative pre-push gate
  check_source_strings.py  # hard-coded Text("...") detector

.claude/agents/
  translation-locale.md    # subagent definition used by step 3 (Read+Write only)

tmp/
  translate-inputs/source.json
  translate-inputs/manifest.json
  translate-prompts/{locale}.md
  translate-outputs/{locale}.json
```
