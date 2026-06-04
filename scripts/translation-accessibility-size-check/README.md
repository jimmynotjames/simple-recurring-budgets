# `translation-accessibility-size-check` — ad-hoc localized-layout screenshot check

A manual, **ad-hoc** check for localized **truncation / overflow / RTL-mirroring** at large Dynamic
Type. It renders the app in 7 locales at forced `.xxxLarge`, captures a screenshot of each key screen,
and leaves them for **visual inspection** (Claude reads them and reports). It is **not** wired into
`make test`, pre-commit, or CI — run it on demand, e.g. **before an App Store submission**.

> Why visual, not assertions: on iOS 26.x `performAccessibilityAudit(for: .textClipped)` is a
> *predictive* heuristic that false-positives on static text / SwiftUI nodes (see issue #171), so it
> can't reliably catch real truncation. A human/Claude eyeballing screenshots is the dependable check.

## Run it

```bash
# Easiest: ask Claude — "run the translation-accessibility-size-check" (the skill warns about
# resources, runs this, reads every screenshot, reports, and offers to clean up).
#
# Or directly (it will refuse without --yes and print the resource warning):
bash scripts/translation-accessibility-size-check/run.sh --yes
```

Output: `tmp/loc-size-check/<lang>__<screen>.png` (gitignored), downscaled for cheap reading. Delete
when done: `rm -rf tmp/loc-size-check`.

## ⚠ Resources
It spins up **`WORKERS` simulator clones in parallel** (default 7) and saturates CPU/RAM while running.
Close other heavy apps first. This intentionally exceeds the repo's `SRB_SIM_MAX` cap (1–3) — it's an
explicit ad-hoc override and does not change that default.

## What it captures (v1)
7 languages — `de` (long Latin), `fi` (agglutinative), `ru` (Cyrillic + plurals), `th` (tall script),
`vi` (stacked diacritics), `ar` + `he` (RTL) — each at `.xxxLarge`, across 7 screens/states: empty
list, multi-budget list (incl. a long name), Add Budget, Settings, Budget detail, detail + options
menu, Add Expense. ≈ 49 screenshots.

## Knobs (env)
- `WORKERS` — parallel clones (default 7 = one per language; raise if you expand the matrix).
- `SIMULATOR_NAME` — base device (default: repo default). A **compact** model (narrow width) is the
  worst case for truncation, e.g. `SIMULATOR_NAME="iPhone SE (3rd generation)"`.
- `MAX_PX` — downscale longest screenshot edge (default 1000) to trade detail for read cost.

## How the size is forced
Via the `FORCE_DYNAMIC_TYPE` env hook (`TestDynamicTypeOverride`, gated by `IS_TESTING`) — the
`-UIPreferredContentSizeCategoryName` launch arg was unreliable on the iOS 26.x simulator. Inert in
production.

## Extending it
- **More languages:** add a `testCaptureXxx()` method + a `localeID` entry in
  `simple-recurring-budgetsUITests/LocalizationScreenshotCapture.swift`.
- **More screens/states:** add a `capture(...)` call in `captureAll`. States needing richer fixtures
  (paused budget, expenses → deficit/surplus chips, the orphan-warning **plural** alert at count 1 vs 5)
  require enriching the test seed (`InMemoryModelContainer.makeForUITests` + `SEED_BUDGETS` spec) and a
  few more `.accessibilityIdentifier`s — a worthwhile follow-up to verify plurals visually.
- **Pseudo-loc:** do **not** use `-NSDoubleLocalizedStrings` for truncation — it corrupts this app's
  positional `%1$@`/`%2$@` specifiers. Use real locales (already the case here).
