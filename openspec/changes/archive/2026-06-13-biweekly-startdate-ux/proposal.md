## Why

Biweekly is the only recurring period whose 14-day grid is anchored to the budget's own `startDate` (daily resets daily; weekly grids on the global Week-Starts-On setting; monthly on the calendar month). That dynamic was invisible on the Add/Edit Budget screen, and editing an existing biweekly budget's start date silently re-slices every past period (and the carry-over figure). The UI and copy fixes for this are already implemented and shipped on the `biweekly-startdate-ux` branch; this change formalizes that behavior in the spec, backfills test coverage, and aligns the docs.

## What Changes

The production behavior below is **already implemented** — this change does not modify UI or copy. It captures the behavior as spec requirements, adds the test coverage that was deferred, and updates the feature doc.

- Spec: a biweekly explanatory caption renders under the Period chips (add + edit) — "Repeating 14-day period. Choose your start date below to choose which day each cycle begins on."
- Spec: selecting Biweekly auto-expands the existing Schedule disclosure so the start date (the cycle anchor) is visible; auto-expand only, never auto-collapse.
- Spec: a Save-time "Change Start Date?" confirmation fires in Edit mode when a biweekly budget's start date changed; when the same edit also strands logged expenses, the orphan sentence folds into the one alert (no stacked alerts).
- Spec: the edit-mode period-lock caption is reworded to "Period type can't be changed after creating your budget." (and the matching VoiceOver hint) — only the period *type* is immutable; dates remain editable.
- Tests: unit coverage for the `isBiweeklyStartDateEdited` gate and the orphan-overlap interaction; a regression test that a biweekly `startDate` edit re-anchors period boundaries; UI screen-object + journey coverage for the note, auto-expand, and the Save-time confirmation.
- Docs: update F-2.03 acceptance criteria (new biweekly UX) and correct the quoted period-lock caption copy.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `add-edit-budget-screen`: adds requirements for the biweekly explanatory note, Schedule auto-expand on biweekly selection, and the Save-time biweekly re-anchor confirmation; modifies the Period-field requirement's locked-caption copy and the localized-strings inventory.

## Impact

- **Already shipped (not changed here):** `simple-recurring-budgets/Views/BudgetForm/AddEditBudgetView.swift`, `AddEditBudgetViewModel.swift`, `AddEditBudgetView+Previews.swift`, and the new/updated keys in `Localizable.xcstrings` (translated to all 49 locales).
- **This change adds:** unit tests under `simple-recurring-budgetsTests/` (`AddEditBudgetViewModelScheduleTests.swift`, `BudgetCalculatorBiweeklyTests.swift`/`PeriodCalculatorTests.swift`); UI coverage in `simple-recurring-budgetsUITests/` (`AddBudgetScreen.swift`, `UserJourneyTests.swift`).
- **No calculator/period-math changes:** the calculators are pure and already re-derive the biweekly anchor from `startDate`; `budget-math` requirements are unaffected.
- **No new analytics:** `budget_edited` already carries `startDateChanged`.

## Doc alignment

Skimmed `docs/main-prd.md` (§6.7 carry-over, §6.8 cross-cutting), `docs/product-features-planning.md` (F-2.03, F-5.01, F-7.05), and `docs/tech-design-doc.md` (testing/MVVM).

- **Conflict with docs (must fix):** `docs/product-features-planning.md` F-2.03 (line ~144) still quotes the old locked caption "This can't be changed after creating your budget." The shipped copy is now "Period type can't be changed after creating your budget." — update during apply.
- **Doc gap (must fill):** F-2.03 has no acceptance criteria for the biweekly note, Schedule auto-expand, or the Save-time re-anchor confirmation. Add them during apply.
- F-7.05 and F-5.01 already state the biweekly-anchored-to-`startDate` rule correctly — no change needed there.
