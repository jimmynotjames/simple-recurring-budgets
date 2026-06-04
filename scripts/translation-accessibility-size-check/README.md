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

## Audit log (durable record)
The screenshots are ephemeral; **[`AUDIT_LOG.md`](AUDIT_LOG.md)** is the lasting record. It holds the
**known issues / decisions** (findings we've inspected and accepted or deferred — consulted so each run
flags only *new* deltas) and a **run history** (one dated verdict per inspection). The skill reads it
before reporting and appends to it after; update it by hand when you run the tool directly.

## ⚠ Resources
It spins up **`WORKERS` simulator clones in parallel** (default 7) and saturates CPU/RAM while running.
Close other heavy apps first. This intentionally exceeds the repo's `SRB_SIM_MAX` cap (1–3) — it's an
explicit ad-hoc override and does not change that default.

## What it captures
10 languages, each chosen to stress a distinct failure mode — `de` (long Latin), `fi` (agglutinative),
`ru` (Cyrillic + plurals), `th` (tall script), `vi` (stacked diacritics), `ar` + `he` (RTL),
`ja` + `zh-Hans` (CJK: no-space line-breaking, ideographic width, tall glyphs at large type),
`hi` (Devanagari: above/below stacking marks + conjuncts — vertical-clipping risk). Each at `.xxxLarge`,
across 7 screens/states: empty list, multi-budget list (incl. a long name), Add Budget, Settings, Budget
detail, detail + options menu, Add Expense. **Add Budget yields two shots** (`03-add-budget` +
`03b-add-budget-lower`): its name field auto-focuses, so the capture dismisses the keyboard and scrolls
to show the full period selector and the schedule / carry-over cards below it. ≈ 80 screenshots
(8 per language).

## Knobs (env)
- `WORKERS` — parallel sim clones (default 7). Need **not** equal the language count — xcodebuild spreads
  the 10 test methods across the workers. Each clone is a full simulator (~1.5–2 GB resident), so ~6–7
  suits a 16 GB machine; more will swap. Lower on smaller RAM; raise only with headroom.
- `SIMULATOR_NAME` — base device (default: repo default). A **compact** model (narrow width) is the
  worst case for truncation, e.g. `SIMULATOR_NAME="iPhone SE (3rd generation)"`.
- `MAX_PX` — downscale longest screenshot edge (default 1000) to trade detail for read cost.

## How the size is forced
Via the `FORCE_DYNAMIC_TYPE` env hook (`TestDynamicTypeOverride`, gated by `IS_TESTING`) — the
`-UIPreferredContentSizeCategoryName` launch arg was unreliable on the iOS 26.x simulator. Inert in
production.

## What it reuses (don't break these without updating the capture)
This check is deliberately thin — it leans on existing app/test infrastructure rather than duplicating it.
If you're modifying any of the following, check `LocalizationScreenshotCapture.swift` first:
- **`UITestHelpers.makeApp()` / `makeApp(seedBudgets:)`** and the **`SEED_BUDGETS`** launch-env contract
  (comma-delimited names → one monthly $100 budget each; **names must not contain commas**).
- **`InMemoryModelContainer.makeForUITests()`** (DEBUG, gated by `IS_TESTING`) — parses `SEED_BUDGETS`.
- Four production-view **`.accessibilityIdentifier`** handles this capture is the *only* consumer of:
  `toolbar.settings.label`, `toolbar.addBudget.accessibilityLabel`, `budget.row.addExpense.accessibilityLabel`
  (BudgetsView) and `budgetDetail.menu.accessibilityLabel` (BudgetDetailView). Each is commented in-view.
- **`TestDynamicTypeOverride`** (the `FORCE_DYNAMIC_TYPE` hook) at the app root.
- **`scripts/_destination.sh`** + **`scripts/build.sh`** (the runner sources/builds through them).
- The capture is **excluded** from `make test` by omission from `scripts/test-ui.sh`'s `-only-testing` list —
  it runs only when `run.sh` targets it. Keep it out of that list.

## Extending it
- **More languages:** add a `testCaptureXxx()` method + a `localeID` entry in
  `simple-recurring-budgetsUITests/LocalizationScreenshotCapture.swift`.
- **More screens/states:** add a `capture(...)` call in `captureAll`. States needing richer fixtures
  (paused budget, expenses → deficit/surplus chips, the orphan-warning **plural** alert at count 1 vs 5)
  require enriching the test seed (`InMemoryModelContainer.makeForUITests` + `SEED_BUDGETS` spec) and a
  few more `.accessibilityIdentifier`s — a worthwhile follow-up to verify plurals visually.
- **Pseudo-loc:** do **not** use `-NSDoubleLocalizedStrings` for truncation — it corrupts this app's
  positional `%1$@`/`%2$@` specifiers. Use real locales (already the case here).
