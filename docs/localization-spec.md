# Localization Spec

> How Wren's strings, App Store listing and screenshot seeds get into 50 languages and stay there:
> the shared pipeline code, the per-app data in `i18n/`, the locale registry, and the rules every
> pipeline run follows. Key and comment rules for Swift live in `docs/tech-design-doc.md` §5.1;
> per-script detail lives in each pipeline's README and skill.

---

## Shared code, per-app data

The pipeline code (`scripts/translate_catalog/`, `translate_audit/`, `translate_metadata/`,
`appstore_metadata.py`, `check_translations.py`, `check_source_strings.py`, `pipeline_tmp.py`, and
the `*-locale` agents) is byte-identical with the sibling app, reChecklist. Change a shared file in
both repos, in the same session where possible. Everything app-specific lives in `i18n/`, read
through `scripts/translate_catalog/app_config.py`:

| File | Holds |
| --- | --- |
| `i18n/app.json` | Brand, protected terms, paths, Xcode names, store fields and `nameMode`, pinned listing terms, field guidance, extra tmp groups |
| `i18n/brief.md` | Wren's prose for the prompt templates, one fragment per template placeholder |
| `i18n/regional_notes.json` / `i18n/cultural_notes.json` | In-app and store-listing notes per locale |
| `i18n/glossary.json` | Agreed per-locale renderings of recurring terms |
| `i18n/glossary_ignore.json` | Repeated English strings that are not terms, each with its reason |
| `i18n/untranslated_allowlist.json` | Deliberately English-identical `(key, locale)` pairs, each with its reason |
| `i18n/distinct_pairs.json` | Key pairs that must never render identically, each with its reason |

A template placeholder with no value raises before any prompt is written, so a missing fragment
can't reach a subagent. The screenshot demo-content pipeline (`scripts/screenshot_content/`) is
Wren's own; it renders through the shared `prompt_render.py` and reads the store notes.

---

## Locale registry

`fastlane/screenshot-config.json` `locales[]` is the single source of truth: 50 rows of
`{runtime, storefront, region, name}`, plus each target's `register` (§Register).
`scripts/translate_catalog/locales.py` reads it; `translate_metadata/metadata_locales.py` derives
the storefront maps from it; `scripts/tests/test_locale_registry.py` pins
`fastlane/metadata-locales.json` and `appstore_metadata.FASTLANE_LOCALES` to it.

Runtime codes are the catalog's codes (`de`, `nb`, `zh-Hans`). Storefront codes are Apple's
(`de-DE`, `no`, `zh-Hans`). They differ often enough that mixing them is the most common mistake in
this area.

---

## Models are pinned deliberately

Sonnet translates ordinary UI strings. Opus does the glossary, the audits, the App Store metadata,
and the screenshot demo content. The agent definitions pin this by alias (`sonnet`, `opus`), so each
agent moves to the newest model in its tier on release; that is deliberate. A new model behind an
alias is not a reason to regenerate: existing strings stay until an audit flags them or a systemic
prompt or rule change invalidates them. Every agent runs at `effort: medium`; do not raise it.

The listing audit is Opus checking Opus, an exception to the rule that the auditor out-classes the
producer. Read it as a consistency pass, not a senior review.

---

## Register

The principle every locale's form of address follows:

> The voice is modern and respectful: current and unfussy, never stiff or old-fashioned, and never
> so casual that it would sound flippant to an older reader. Use the informal address where people
> of every generation would expect it from a modern app, and the polite form where that is still
> the respectful norm.

Audience age is not the test. The call is made **once per locale, by Opus**, and recorded twice
over: as the registry's `register` field (`{"level": "polite", "form": "vous"}`), and in that
locale's notes as the concrete form plus where warmth comes from instead.
`test_locale_registry.py` fails if either note map stops stating the registry's form. Translators
follow the note; they never re-decide it string by string. The recurring failure is system text
(error messages, Settings footers, VoiceOver hints), so the prompts name it. Short button labels
are exempt: they keep the glossary's form.

---

## The App Store listing

`name` is "Wren – <descriptor>" (`nameMode: "descriptor"`), and the descriptor is transcreated per
storefront. The listing uses the app's own words for its core concepts: `metadata.glossaryTerms`
(Budget, Expense, Carry-Over, Biweekly) render as an "agreed terms" section in both the
transcreation and the listing-audit prompts. `keywords` are limited to 100 UTF-8 bytes, not
characters. An unused field has no file; `appstore_metadata.py prepare` rejects an empty one.

---

## Running the pipelines

- **Clean `tmp/` between runs** with `scripts/pipeline_tmp.py clean <group>`. The merge step reads
  every file in an outputs dir, so a stale `tmp/translate-outputs/de.json` from a previous run
  merges silently: last week's translation with this week's keys.
- **The per-locale notes are two maps on purpose.** `i18n/regional_notes.json` (in-app) and
  `i18n/cultural_notes.json` (store listing) differ in wording and market advice (#173), so they are
  not a DRY violation to fix. The formality call itself is one decision: change the registry's
  `register` first, then both notes; the registry test fails until the three agree.
- **No ad-hoc Python.** Every step, inspection included, is a flag on a pipeline script. Reaching
  for `python3 -c` or a throwaway `tmp/*.py` means a script is missing a flag: extend the script.
- **Fan out in batches, named agents only.** Send about 8–12 agent calls per message with
  `run_in_background: true`, and never put a `Bash` call in the same message: one failed call
  cancels its whole batch. Dispatch the pipeline's own `*-locale` agent, never `general-purpose`.
  On a tool without a subagent primitive (Cursor), run the step inline and serially: read each
  prompt file, produce the JSON yourself, write the matching output file. Same scripts, same gates.

---

## Gates

| Check | Where | Blocking |
| --- | --- | --- |
| `check_translations.py` | `make i18n-check` (in `make gate`), pre-push, CI | Yes |
| `check_source_strings.py` | `make i18n-check` (in `make gate`), pre-push, CI | Yes |
| `untranslated_copies.py` | `make i18n-check` (in `make gate`), CI | Yes |
| `distinct_pairs.py` | `make i18n-check` (in `make gate`) | Yes |
| `sync_catalog.py --check` | `make i18n-sync-check`, after the build in `make gate` | Yes |
| `check_metadata.py` | `push_metadata` lane, CI | Yes |
| `plural_completeness.py` | `audit-translations` skill, CI | Yes |
| `consistency_check.py` | `audit-translations` skill, CI | No, informational |
| `check_source_voice.py` | `push_metadata` lane | No, advisory |
| `check_content.py` | Screenshot lanes | Yes |

---

## Large-type layout check

`scripts/translation-accessibility-size-check/` drives a set of locales through the key screens at
forced `.xxxLarge` and leaves the screenshots for reading. It asserts nothing and is deliberately
outside the app test suites and `make gate`. Findings go in its `AUDIT_LOG.md`.
