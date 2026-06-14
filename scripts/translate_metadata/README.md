# `translate_metadata/` — App Store listing transcreation pipeline

Fills `fastlane/metadata/<storefront>/*.txt` for all 49 target App Store
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

> **Per-storefront register notes are intentionally duplicated** between this pipeline's
> `CULTURAL_NOTES` (in `dispatch_prompts.py`) and the in-app pipeline's `REGIONAL_NOTES`
> (`scripts/translate_catalog/dispatch_prompts.py`). They overlap only in the *formality
> decision* per language; the surrounding guidance is genuinely different (ASO
> positioning/keyword rules + marketer voice here vs UI dialect/length there). Issue #173
> considered single-sourcing them and we **decided not to** — the shared-prose abstraction
> required a per-storefront override that re-duplicated the formality sentence anyway. **Sync
> rule:** if you change a market's *formality decision* in one map, change it in the other;
> wording may differ but the formality call must match. (Don't re-file this as a DRY bug.)

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

## The recipe (driven by the `appstore-translate-metadata` skill / `/appstore:translate-metadata`)

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
#    Inspect outputs / collect content questions WITHOUT ad-hoc shell:
python3 scripts/translate_metadata/audit.py             # field/char table + status
python3 scripts/translate_metadata/audit.py --questions # only the _questions batch
python3 scripts/translate_metadata/merge.py

# 5. Semantic audit + remediation (the refine pass) — Opus auditor per storefront,
#    then re-transcreate what it flags at/above medium severity. See
#    "Auditing metadata quality" below. The skill drives this loop autonomously.
python3 scripts/translate_metadata/audit_semantic.py --dispatch
#    fan out metadata-audit-locale (Opus) → tmp/metadata-audit-outputs/{sf}.json
python3 scripts/translate_metadata/audit_semantic.py --report --min-severity medium
python3 scripts/translate_metadata/audit_semantic.py --write-manifest --min-severity medium
#    then dispatch_prompts.py → metadata-locale (with findings) → validate → merge → re-audit

# 6. Authoritative gate — walks fastlane/metadata/ directly.
python3 scripts/translate_metadata/check_metadata.py
```

`check_metadata.py` exiting 0 is the definition of done.

## Files

```
scripts/translate_metadata/
  metadata_locales.py   # storefront list, runtime→storefront map, field limits, brand, names
  extract.py            # en-US/*.txt → tmp/metadata-inputs/source.json (+ --missing → manifest.json)
  dispatch_prompts.py   # source + manifest + PROMPT_TEMPLATE.md → tmp/metadata-prompts/{storefront}.md
  validate.py           # --subset; PASS/PENDING/FAIL; char limits, brand prefix, keyword hygiene; --json
  audit.py              # inspect outputs: field/char table, OVER flags, consolidated _questions; --questions/--json/--full
  merge.py              # tmp/metadata-outputs/{storefront}.json → fastlane/metadata/{storefront}/*.txt + URL passthrough; clears fields blank in en-US
  check_metadata.py     # authoritative gate over fastlane/metadata/ (authored fields populated+within limits; blank-source fields stay empty)
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

## Auditing metadata quality

Two complementary audits:

- **`audit.py`** — *structural*: presence + char-limit (`OVER`/`PENDING`) over the `tmp/`
  fan-out, plus the consolidated `_questions` checkpoint. Already part of the translate recipe.
- **`audit_semantic.py`** — *semantic*: grades the **committed** localized listing
  (`fastlane/metadata/<storefront>/`) for voice, transcreation (native vs. calqued), **keyword/ASO
  effectiveness**, cultural fit, brand, and false claims — one Opus auditor per storefront, mirroring
  the in-app `scripts/translate_audit/` pipeline.

  ```bash
  python3 scripts/translate_metadata/audit_semantic.py --dispatch          # → tmp/metadata-audit-prompts/{sf}.md
  # fan out one metadata-audit-locale (Opus) agent per prompt → tmp/metadata-audit-outputs/{sf}.json
  python3 scripts/translate_metadata/audit_semantic.py --report --min-severity medium
  ```

  It only audits storefronts that actually have localized metadata (reports "nothing to audit"
  otherwise). Run it after a transcreation round to catch quality issues a length check can't.

  **Remediation (`--write-manifest`).** To act on the findings instead of just reading them,
  turn them into a re-transcreation manifest and re-run the standard transcreation path:

  ```bash
  python3 scripts/translate_metadata/audit_semantic.py --write-manifest --min-severity medium
  # → tmp/metadata-inputs/{manifest,source}.json scoped to the flagged (storefront, field) pairs
  python3 scripts/translate_metadata/dispatch_prompts.py     # regenerate prompts for just those
  # fan out metadata-locale (Opus), each told to read BOTH its prompt AND
  #   tmp/metadata-audit-outputs/{sf}.json (the findings), then fix the flagged fields
  python3 scripts/translate_metadata/validate.py --subset && python3 scripts/translate_metadata/merge.py
  # then re-audit the remediated storefronts; loop (cap 2 rounds)
  ```

  This is the `appstore-translate-metadata` skill's Step 5 (it runs the whole loop autonomously:
  auto-remediate medium+ findings, cap 2 rounds, surface any residual for owner review). It mirrors
  the in-app `scripts/translate_audit/audit_report.py --write-manifest` flow.
