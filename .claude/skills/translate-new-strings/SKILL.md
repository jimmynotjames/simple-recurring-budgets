---
name: translate-new-strings
description: Add, change, rename, pluralize, or remove Localizable.xcstrings keys and translate them into every locale. Use after adding any String(localized:) or Text key, for String Catalog or plural work, or when check_translations.py fails.
---

# Translate new strings

Drives `scripts/translate_catalog/` in subset mode. Run everything from the repo root. Script
flags and file layout: `scripts/translate_catalog/README.md`.

**Done when** `python3 scripts/check_translations.py` exits 0. Anything else is not done; loop back.

Pipeline rules: `localization-spec.md §Running the pipelines` and §Models are pinned deliberately.
Never hand-edit the catalog.

## Pre-flight

```bash
python3 scripts/pipeline_tmp.py status translate
python3 scripts/pipeline_tmp.py clean translate
```

## 0. Catalog maintenance

Run whichever applies before step 1. Each script takes JSON from a file or from stdin (`-`); a
heredoc works for small batches. All are allowlisted.

| Change | Command | Input | Then |
|---|---|---|---|
| New key in Swift, not in the catalog | `add_keys.py -` | `{"key": {"comment": "…", "value": "English"}}` (the Swift `comment:` verbatim) | step 1. `--force` overwrites. Also takes over a key a build in Xcode or `make i18n-sync` added (English still `new`). |
| Translator comment changed in Swift, English unchanged | `make build`, then `make i18n-sync` | — | commit the catalog; no re-translation. |
| English text changed | `update_keys.py -` | `{"key": {"value": "New English", "comment": "optional"}}` | step 1 (non-`en` marked `needs_review`). Refuses plural keys: follow its message (`add_keys.py --force` with the comment, then `pluralize_keys.py`). |
| Key renamed, text unchanged | `rename_keys.py -` | `{"old.key": "new.key"}` | update the Swift call sites; no re-translation. `--dry-run`, `--force`. |
| Count string reads wrong at 1 | `pluralize_keys.py -` | `{"key": {"one": "%lld item", "other": "%lld items"}}` (`other` required) | step 1; locales re-translate as plurals. `--dry-run`. |
| Translation must change, English unchanged (e.g. a glossary term changed) | `invalidate_keys.py --keys k1,k2` or `--keys-file tmp/keys.txt` | — | step 1. `--locales`, `--dry-run`. |
| Key no longer used in Swift | `remove_keys.py --keys k1,k2` or `--keys-file …` | — | `--dry-run` first. `make i18n-sync` marks such keys `stale`. |

Scripts live in `scripts/translate_catalog/`, e.g.:

```bash
python3 scripts/translate_catalog/add_keys.py - << 'EOF'
{ "my.feature.title": { "comment": "Title shown on the My Feature screen", "value": "My Feature" } }
EOF
```

No script finds orphaned keys or stale call sites. Grep for them: after a rename, `git grep -n
'old.key'` must return nothing; before removing a key, `git grep -n 'the.key' -- '*.swift'` must
return nothing.

## 1. Detect what needs translating

```bash
python3 scripts/translate_catalog/extract.py --missing
```

Writes `tmp/translate-inputs/source.json` and `manifest.json` (`{locale: [keys]}`). If it reports
nothing missing or stale, run `check_translations.py` and `check_source_strings.py`, then step 5 or
6. To force specific keys: `--keys k1,k2`.

## 2. Compose per-locale prompts

```bash
python3 scripts/translate_catalog/dispatch_prompts.py
```

Writes `tmp/translate-prompts/{locale}.md`, plus `{locale}.sample.md` for locales with pending
demo-content keys (i18n/app.json `transcreatedNamespaces`; none means no sample prompts). It also deletes the manifest locales' old
outputs; `--no-clean` keeps them.

## 3. Translate each prompt file

For every prompt file, dispatch one agent. The prompt is complete: never add rules in the dispatch
message. If a rule is missing, fix `PROMPT_TEMPLATE.md` or `SAMPLE_PROMPT_TEMPLATE.md`.

| Prompt | `subagent_type` | Output |
|---|---|---|
| `tmp/translate-prompts/{locale}.md` | `translation-locale` | `tmp/translate-outputs/{locale}.json` |
| `tmp/translate-prompts/{locale}.sample.md` | `sample-content-locale` | `tmp/translate-outputs/{locale}.sample.json` |

Dispatch message: "Read `<abs>/tmp/translate-prompts/ja.md` and follow it. Write the JSON object
(nothing else) to `<abs>/tmp/translate-outputs/ja.json`." Never use `general-purpose`: the named
agents pin the model and restrict the tools.

## 4. Validate, merge, and check

Once the outputs exist, run the tail as one command:

```bash
python3 scripts/translate_catalog/validate.py --subset \
  && python3 scripts/translate_catalog/merge.py \
  && python3 scripts/check_translations.py \
  && python3 scripts/check_source_strings.py
```

If `validate.py --subset` fails for a locale (usually a dropped or duplicated `%@` / `%lld`),
re-dispatch that locale's agent and re-run the chain. `merge.py` never overwrites a non-empty entry
with an empty one, and promotes a merged key's English from `new` to `translated`.

## 4b. Keep the glossary current

```bash
python3 scripts/translate_catalog/glossary_sync.py --detect
```

If it reports new high-confidence terms (`tmp/glossary/terms.json`; skim
`tmp/glossary/candidates_review.json` too), add them:

```bash
python3 scripts/translate_catalog/glossary_build.py --dispatch
# one glossary-locale agent per tmp/glossary/prompts/{locale}.md → tmp/glossary/outputs/{locale}.json
python3 scripts/translate_catalog/glossary_build.py --merge
```

Skip this step if `--detect` reports nothing new.

## 5. If the checks fail

- Missing or stale `(key, locale)` pairs: `extract.py --keys k1,k2`, then step 2.
- `check_source_strings.py` failure: an unkeyed literal in Swift. Key it, then rerun this skill.
- `NEW [en] '<key>' (source)` on a key whose locales were already complete: `extract.py --keys
  <key>`, then the step-4 chain.

## 6. Gate

```bash
make gate
```

If Swift changed too, also `L=tmp/unit-tests-$$.log; make unit-tests > "$L" 2>&1; echo "$? $L"` (AGENTS.md §"Reading a
test result").

## 7. Cleanup

Ask first; the outputs are handy for inspecting a locale. On a yes:

```bash
python3 scripts/pipeline_tmp.py clean translate
```

Regenerating every locale is not this skill: `scripts/translate_catalog/README.md`.
