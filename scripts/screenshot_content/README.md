# screenshot_content — App Store screenshot demo-content pipeline

Generates the **culturally-tuned, per-locale demo data** the Wren app is seeded
with when capturing App Store marketing screenshots (≤3 budgets per locale with
locally realistic names, emoji, currency, and amounts).

It is the screenshot sibling of the in-app (`translate_catalog/`) and metadata
(`translate_metadata/`) pipelines and follows the same shape:
**extract → dispatch → fan-out subagents → validate → merge → gate.**

The driver is the **`/appstore:generate-screenshot-seeding`** command (skill
`appstore-generate-screenshot-seeding`); this directory holds the scripts it runs.
Capture and upload are driven by the **`/appstore:generate-push-screenshots`** skill.

## What it produces

A runtime-keyed JSON catalog under
`simple-recurring-budgetsUITests/ScreenshotSeeds/<runtime>.json` (en-US + 49
target runtimes). The catalog lives in the **UI test target** so the marketing
fixtures never ship in the production app. The `AppStoreScreenshots` UI test loads
the file matching the `-AppleLanguages` value fastlane `snapshot` launches with
and seeds the app via the `SEED_SCREENSHOTS_JSON` launch-env contract.

Each file also carries a top-level **`primaryLocale`** — the region-qualified ICU
locale identifier (`de_DE`, `ja_JP`, `nb_NO`, …) the UI test passes as
`-AppleLocale`. fastlane only sets `-AppleLanguages`, so language-only locales stay
region-less and `Locale.currency` resolves to nil, making the Settings
currency-display example fall back to USD; `primaryLocale` pins the market so every
shot shows the right currency and number formatting. The value is owned by
`REGION_BY_STOREFRONT` in `content_locales.py` (kept 1:1 with the currency map) and
the production `ScreenshotSeed` decoder ignores the key.

## Locale codes

- Subagent work is keyed by **storefront** codes (de-DE, no, ar-SA, …), reusing
  `translate_metadata/metadata_locales.py` for the mapping + cultural notes.
- The merged catalog is keyed by **runtime** codes (de, nb, ar, …) — the exact
  Snapfile `-AppleLanguages` strings. `merge.py` maps storefront → runtime.
- After capture, `rename_for_deliver.py` renames the captured
  `fastlane/screenshots/<runtime>/` folders back to storefront codes so `deliver`
  finds valid App Store Connect locale folders.

## Source of truth

`SOURCE.json` — the canonical English budget **structure**. Structural fields
(`role`, `period`, `startOffsetDays`, `isCarryOverEnabled`, expense `daysAgo`,
expense count) are preserved by every locale; only content (`name`, `icon`,
`currencyCode`, `allocation`, expense `name`/`amount`) is tuned. This keeps every
locale's screenshots structurally identical while culturally distinct, and keeps
the carry-over chip showing a surplus on the daily food budget.

## Recipe

```bash
# 1. Stage source + compute the work manifest (missing-only for incremental runs)
python3 scripts/screenshot_content/extract.py --missing

# 2. Compose one prompt per storefront
python3 scripts/screenshot_content/dispatch_prompts.py

# 3. Fan out one screenshot-content-locale subagent per storefront (Claude Code),
#    each reading tmp/screenshot-content-prompts/{storefront}.md and writing
#    tmp/screenshot-content-outputs/{storefront}.json. (Cursor / no-subagent
#    tools: do the same inline + serially.)

# 4. Validate produced outputs, then merge into the catalog
python3 scripts/screenshot_content/validate.py --subset
python3 scripts/screenshot_content/merge.py

# 5. Gate
python3 scripts/screenshot_content/check_content.py
```

`validate.py` reports PASS / WARN / PENDING / FAIL per storefront (your retry
dashboard). Re-dispatch only the PENDING/FAIL subagents; do **not** re-run
`dispatch_prompts.py` mid-fan-out (it clears outputs by default).

## Files

| File | Role |
| --- | --- |
| `content_locales.py` | Config: locale mapping (reused), currency-by-storefront, region-by-storefront, decimals, paths, MAX_BUDGETS. |
| `SOURCE.json` | Canonical English structure (the en-US catalog entry too). |
| `PROMPT_TEMPLATE.md` | Per-locale transcreation prompt (rules + realism anchors). |
| `extract.py` | Stage source + compute manifest (`--missing`). |
| `dispatch_prompts.py` | Compose per-storefront prompts (reuses metadata `CULTURAL_NOTES`). |
| `validate.py` | Structural + content validation (`--subset`, `--json`). |
| `merge.py` | Write runtime-keyed catalog + en-US source entry (incl. `primaryLocale`). |
| `set_primary_locales.py` | Deterministic backfill/sync of `primaryLocale` into the committed catalog (no regen); `--check` to gate. |
| `check_content.py` | Completeness gate over the catalog (incl. `primaryLocale`). |
| `rename_for_deliver.py` | Rename captured screenshot folders runtime → storefront. |

## Not in scope

- App Store **text** metadata → `/appstore:translate-metadata`.
- In-app UI strings → `translate-new-strings`.
- Capture + upload mechanics → `fastlane/Snapfile`, `fastlane/Fastfile`
  (`screenshots` / `push_screenshots` lanes), `fastlane/SETUP.md`.
