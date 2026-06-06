---
name: appstore-translate-metadata
description: Transcreate the App Store listing (name, subtitle, keywords, promotional text, description, release notes) from English into all 49 App Store storefront locales under fastlane/metadata/. Invoked via /appstore:translate-metadata. Use after editing any fastlane/metadata/en-US/*.txt, or when check_metadata.py reports gaps. Drives the scripts/translate_metadata/ pipeline in subset mode with parallel per-storefront Opus subagents. This is the App-Store-metadata sibling of translate-new-strings (in-app strings) and appstore-screenshot-content (screenshot demo data).
---

# Translate App Store metadata

Canonical recipe for getting `fastlane/metadata/` to a fully-transcreated state
after authoring or editing the English (`en-US`) listing copy. Drives the
existing `scripts/translate_metadata/` pipeline in subset mode.

**Definition of done:** `python3 scripts/translate_metadata/check_metadata.py`
exits 0 — every translatable field the English source has authored is populated
and within its character limit across all 49 target storefronts.

This is the **metadata** pipeline (App Store listing). For in-app UI strings in
`Localizable.xcstrings`, use the separate `translate-new-strings` skill. They use
different locale code systems (storefront vs runtime); `metadata_locales.py` owns
the mapping.

## Autonomy

Run this whole pipeline **autonomously, end to end, without pausing for approval
on mechanical steps** — extract, dispatch, fan-out, validate, merge, and the gate
are all routine and pre-approved in `.claude/settings.json`. Do **not** ask "shall
I proceed?" between steps, and do not ask permission to retry a failed locale.

There is exactly **one** thing worth bringing to the human: **genuine content
questions about the marketing copy itself** that the subagents flag (Step 4a).
Surface those in a single batch; everything else you decide and execute yourself.

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
- **Register notes are intentionally duplicated — keep them in sync, don't DRY them.**
  The per-storefront formality guidance in `CULTURAL_NOTES` (`scripts/translate_metadata/dispatch_prompts.py`)
  deliberately overlaps with the in-app `REGIONAL_NOTES` only on the *formality decision* per
  language (issue #173, closed without consolidation). If you change a market's formality decision
  (e.g. de-DE "du"→"Sie") here, mirror it in `REGIONAL_NOTES`; wording may differ, the formality
  call must not. Don't try to merge the two maps.

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

### 3. Transcreate each storefront's slice

> **Cross-tool execution.** On **Claude Code**, dispatch one `metadata-locale` subagent per storefront
> in parallel (below). On **Cursor** or any tool without a subagent primitive, run the same step
> **inline and serially**: for each `tmp/metadata-prompts/{storefront}.md`, read it, produce the
> transcreation JSON yourself, and write `tmp/metadata-outputs/{storefront}.json` — then continue.
> Same scripts, same gates, same result. Canonical: `AGENTS.md > Cross-cutting concerns > Running the
> translation pipelines`.

#### Claude Code — one `metadata-locale` subagent per storefront, in parallel

For every `tmp/metadata-prompts/{storefront}.md` that exists, invoke an `Agent`:

- `subagent_type`: `metadata-locale` (defined in `.claude/agents/metadata-locale.md`,
  Read+Write only, model **opus**).
- A short dispatch prompt naming the input and output paths. Example:
  > Read `/abs/path/tmp/metadata-prompts/de-DE.md` and follow the rules in it.
  > Write the resulting JSON object (nothing else) to
  > `/abs/path/tmp/metadata-outputs/de-DE.json`.

Do not pass `subagent_type: general-purpose` — the narrow agent is what keeps the
dispatches auto-approvable in `.claude/settings.json`.

**Batch the dispatches, and keep agent calls separate from shell/script calls.**
Send the subagent calls concurrently in batches (e.g. ~8–12 per message) rather
than all 38 plus shell commands in one giant message. Never mix `Agent` calls and
`Bash` calls in the same message: if one tool call errors (a hygiene-blocked
command, a "nothing to commit", etc.) the whole parallel batch is cancelled,
killing in-flight subagents and wasting their work. Run scripts (extract,
dispatch, validate, merge, audit) in their own single-purpose messages, and keep
each `Bash` message to one command so one failure can't cascade.

The prompt file already contains every rule (brand, char limits, keywords-as-search,
tone/register, JSON-only). Do not modify it in the dispatch message.

### 4. Validate, then merge

```bash
python3 scripts/translate_metadata/validate.py --subset
```

`--subset` checks only the fields present in each output file and reports one of
three per-storefront states — your retry dashboard:
- **PASS** — valid, within limits, ready to merge.
- **PENDING** — empty/missing output: the subagent hasn't run or produced
  nothing. Action: **(re)dispatch that one storefront.** Not an error.
- **FAIL** — produced content but it's broken. Common causes:
  - **Over the character limit** (especially `name`/`subtitle` at 30, and
    `keywords` at 100 — the single most common failure) — re-dispatch; the prompt
    tells the model to tighten until it fits.
  - **`name` missing the brand prefix** — re-dispatch.
  - **Keyword hygiene warnings** (spaces after commas, dupes) are warnings, not
    failures, but re-dispatch if egregious.

**To retry, re-dispatch only the PENDING/FAIL subagents** (the prompt files are
still in `tmp/metadata-prompts/`). **Do NOT re-run `dispatch_prompts.py` to
retry** — by default it clears every manifest locale's output, wiping locales that
already succeeded. (Re-running the full extract→dispatch→merge loop is safe
because merged locales drop out of the next manifest; it's only re-running
`dispatch_prompts.py` *mid-fan-out* that's destructive.)

**Do not write ad-hoc Python/`wc`/`cat`/`jq` to inspect outputs or count
characters.** Everything you need is in two pre-approved tools:
- `validate.py --subset [--json]` — pass/pending/fail + every hard error.
- `audit.py [storefront …]` — per-field char counts vs. limits with OVER flags,
  and the consolidated `_questions` batch (see Step 4a). Add `--json` for a
  machine-readable summary, `--full` for untruncated values.

Once `validate.py --subset` exits 0:

```bash
python3 scripts/translate_metadata/merge.py
```

Writes each field to `fastlane/metadata/{storefront}/{field}.txt` and copies the
URL files verbatim from en-US. Refuses to clobber a non-empty file with an empty
value. The `_questions` arrays (if any) live only in the `tmp/metadata-outputs/`
JSON — `merge.py` strips `_`-prefixed keys, so they never reach the metadata tree.

### 4a. Collect and surface content questions (the one human checkpoint)

The subagents are instructed to **work autonomously** and only attach a top-level
`_questions` array when they hit a genuine *content* decision about the marketing
copy (a concept with no natural equivalent, a claim that's culturally/legally
risky in-market, a load-bearing phrase that can't fit a 30-char field, or
genuinely ambiguous source English). They always still write a best-effort
translation, so the pipeline is never blocked.

Collect them with the pre-approved tool — **do not hand-roll this with `cat`/`jq`/
`python3 -c`:**

```bash
python3 scripts/translate_metadata/audit.py --questions
```

This prints every `_questions` entry across all locales (locale, field, issue, and
the subagent's default decision) in one batch, or "No content questions raised" if
there are none. Present that batch to the human **in a single consolidated
message** (group by issue where the same question recurs across locales) so they
can accept each default or override it. Use `AskUserQuestion` (or a concise
written summary) — do **not** dribble out one prompt per locale, and do **not**
stall the rest of the pipeline waiting on answers: the metadata is already merged
and valid; these questions are about *improving* specific strings, not unblocking
the run.

If there are **no** `_questions`, say so briefly and continue — this is the
expected case. Do not invent questions or ask for approval you don't need.

If the human overrides a default, apply the change by editing the relevant
`fastlane/metadata/<storefront>/<field>.txt` directly (or re-dispatching that one
locale with the added guidance), then re-run `validate.py` + `check_metadata.py`.

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
