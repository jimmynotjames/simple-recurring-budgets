# budgets-screen delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: Row eagerly refreshes carry-over and remaining via the lifecycle service

Each row SHALL invoke `BudgetLifecycleService.result(for:)` for its budget:

- On task initialization keyed by the budget's `persistentModelID` (so the call is re-issued when the row's identity changes, e.g. row recycling).
- On `scenePhase` becoming `.active` while the row is on screen (so any period or reset boundaries crossed while the app was inactive are applied before the next render).
- On `onChange(of: settings.weekStartDay)` (so a Week Starts On change — confirmed locally in Settings or synced from another device via the iCloud key-value store — re-grids weekly rows immediately).

The row SHALL pass `weekStart: settings.weekStartDay` per the `budget-lifecycle` capability. The row SHALL bind the returned `BudgetLifecycleResult.remaining` and `BudgetLifecycleResult.carryOverAmount` for display. When the lifecycle result is unavailable (initial state before the first call returns), the row MAY fall back to the budget's persisted `carryOverAmount`. The row SHALL NOT call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly — `BudgetLifecycleService` is the sole entry point for the eager sequence.

#### Scenario: Refresh on row appearance

- **WHEN** the Budgets screen renders a row for a budget
- **THEN** `BudgetLifecycleService.result(for:)` is called for that budget within the row's `.task(id: budget.persistentModelID)`, and the returned `remaining` and `carryOverAmount` are bound to the row's display

#### Scenario: Refresh on scene activation

- **WHEN** the app transitions from `.inactive` or `.background` to `.active` while the Budgets screen is visible
- **THEN** each visible row re-invokes `BudgetLifecycleService.result(for:)` and re-binds the returned values

#### Scenario: Refresh on week-start change

- **WHEN** `AppSettings.weekStartDay` changes while Budgets rows are visible
- **THEN** each visible row re-invokes `BudgetLifecycleService.result(for:)` with the new `weekStart` and re-binds the returned values
