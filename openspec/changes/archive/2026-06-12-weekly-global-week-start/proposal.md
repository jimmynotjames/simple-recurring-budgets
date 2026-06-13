## Why

Issue #240: changing **Week Starts On** in Settings has no effect on existing weekly budgets — each weekly budget privately derives its week grid from its own `startDate` weekday (the F-5.01 scope clarification shipped with `rewrite-budget-calculations`). The Settings confirmation alert meanwhile promises the opposite ("will immediately affect all weekly and biweekly budgets"), and nothing in the UI ever displays a budget's private anchor, so the common user gets a surprising hidden grid while the copy lies. Product decision (with the owner, 2026-06-12): reverse the scope decision — weekly budgets follow the global setting at math time, the same way monthly budgets all share the calendar-month grid. The app is pre-launch, so retroactive re-gridding has no installed-base cost; this is the cheapest moment to fix the model.

Issue #247 (found by the pre-#240 test-hardening pass): `BudgetLifecycleService.applyAllocationEdit` inserts the edited `AllocationChange` row at `currentPeriodStart`, while the live read looks up at `max(currentPeriodStart, effectiveStartDate)` — so an edit made during a mid-grid *first* period is shadowed (live shows the old amount; the walker later uses the new one). Today only monthly budgets created mid-month can hit it; the weekly global grid makes weekly budgets susceptible too, so the fix lands in this same change, first.

## What Changes

- **Weekly budgets use the global week grid.** `BudgetCalculator.snapshot` gains an explicit `weekStart: Weekday` parameter (no default); callers pass `AppSettings.weekStartDay`. The per-budget weekday derivation from `startDate` is deleted. `startDate` keeps defining when the budget begins and remains the **biweekly** cycle anchor — biweekly behavior is unchanged (a weekday cannot define a 14-day cycle's phase). Daily/monthly unaffected.
- **`BudgetLifecycleService`** threads the same parameter through `result`, `applyAllocationEdit`, `pauseBudget`, `resumeBudget`, `resetBudget` (`resetCarryOver` does no period math and is unchanged).
- **#247 fix — governing-row mutate rule** in `applyAllocationEdit`: edit key becomes `max(currentPeriodStart, startOfDay(effectiveStartDate))`, and the edit mutates the row currently governing the period when that row took effect within the current period, else inserts at the key. Live read, walker, and write now agree in mid-grid first periods.
- **Settings copy** becomes truthful and weekly-only: alert message and accessibility hint for the Week Starts On picker reworded (biweekly dropped; history-regroup consequence stated). Translations refreshed for all locales.
- **Reactivity**: Budgets list rows and Budget detail refresh their lifecycle results when `settings.weekStartDay` changes (covers in-session and iCloud-synced remote changes).
- **BREAKING** (behavioral, pre-launch): existing weekly budgets with non-default start weekdays re-grid onto the global week; historical per-week sums regroup and carry-over values recompute. Custom per-budget weekly anchors cease to exist (biweekly remains the payday-cadence tool).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `budget-math`: weekly period-start computation uses the caller-provided global `weekStart` (the SHALL-NOT-consult-AppSettings rule is inverted); `snapshot` signature gains the parameter.
- `budget-lifecycle`: service entry-point signatures gain `weekStart`; the allocation-edit write-path adopts the governing-row mutate rule (#247).
- `settings-screen`: Calendar-section cascade scope (weekly-only, immediate, history regroups) and the alert/a11y copy.
- `add-edit-budget-screen`: the Edit-branch save path now reads `settings.weekStartDay` (previously "SHALL NOT read settings at all"); the Thursday-anchor scenario inverts.
- `budgets-screen` / `budget-detail-screen`: eager-refresh trigger lists gain `onChange(of: settings.weekStartDay)`.
- `data-models`: one-line rationale tweak on weekly/biweekly `startDate` seeding (behavior unchanged).

## Impact

- `simple-recurring-budgets/Domain/BudgetCalculator.swift`, `BudgetLifecycleService.swift`, `PeriodCalculator.swift` (docs only).
- Views/VMs threading the parameter: `BudgetsView`, `BudgetDetailView` (+PauseResume), `AddEditBudgetViewModel`, `AddEditExpenseViewModel` (+ its previews/callers), `RootView`, `RatingPromptCoordinator`.
- `SettingsView` strings + `Localizable.xcstrings` (2 keys × all locales, via translate-new-strings).
- Tests: Group B pin suites flip per their banners; all snapshot/service test calls gain the explicit parameter (Group A arithmetic unchanged — the regression guarantee from PR #248's hardening commit); 4 new tests.
- Docs: `product-features-planning.md` (F-5.01, F-7.05, F-2.03), `tech-design-doc.md`, `budget-calculations-rewrite-algorithm.md`, one-line note in `budget-calculations-rewrite-reqs.md`.
- Closes #240 and #247.

## Doc alignment

This change deliberately **reverses** the documented F-5.01 scope clarification and algorithm-doc §A.4.1 weekly-anchor rule; updating those passages is in-scope task work, not drift. `main-prd.md` needs no changes (verified: no anchoring mentions).
