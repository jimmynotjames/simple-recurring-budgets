# budget-detail-screen delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: Eager lifecycle refresh on task, scene-active, and expense-count change

The screen SHALL invoke `BudgetLifecycleService.result(for:)` for the bound `Budget` on four triggers:

1. `.task(id: budget.persistentModelID)` — initial load and identity changes.
2. `onChange(of: scenePhase)` when the new phase equals `.active`.
3. `onChange(of: budget.expenseItems.count)` — every insert or delete from the Add Expense sheet, swipe-to-delete, or Reset Budget operation.
4. `onChange(of: settings.weekStartDay)` — a Week Starts On change (confirmed locally in Settings or synced from another device via the iCloud key-value store) re-grids weekly budgets immediately.

The screen SHALL pass `weekStart: settings.weekStartDay` per the `budget-lifecycle` capability. The screen SHALL bind the returned `BudgetLifecycleResult` to a `@State` property and use it to drive the header `remaining`, `carryOverAmount`, and `periodStart` (used by the section partitioning). The screen SHALL NOT call `BudgetCalculator.rollCarryOver` or `checkScheduledReset` directly — `BudgetLifecycleService` is the sole entry point for the eager sequence (consistent with `docs/tech-design-doc.md` §5.4).

When the lifecycle result is unavailable (initial state before the first call returns), the screen MAY fall back to the budget's persisted `carryOverAmount` for chip rendering and SHALL evaluate the section partitions as empty arrays (showing the empty-budget caption) until the result resolves.

#### Scenario: Refresh on screen appearance

- **WHEN** `BudgetDetailView` first appears for a budget
- **THEN** `BudgetLifecycleService.result(for:)` is called once within `.task(id: budget.persistentModelID)` and the returned `remaining`, `carryOverAmount`, and `periodStart` are bound to the view's state

#### Scenario: Refresh on scene activation

- **WHEN** the app transitions from `.inactive` or `.background` to `.active` while `BudgetDetailView` is visible
- **THEN** `BudgetLifecycleService.result(for:)` is invoked again so any boundaries crossed while the app was inactive are applied before the next render

#### Scenario: Refresh on expense count change

- **WHEN** `budget.expenseItems.count` changes (via Add Expense sheet, swipe-to-delete, or Reset Budget confirmation)
- **THEN** `BudgetLifecycleService.result(for:)` is invoked so the header re-derives `remaining` and the section partitioning re-evaluates against the latest set

#### Scenario: Refresh on week-start change

- **WHEN** `AppSettings.weekStartDay` changes while `BudgetDetailView` is visible
- **THEN** `BudgetLifecycleService.result(for:)` is invoked with the new `weekStart` so the header period label, `remaining`, and `carryOverAmount` re-derive on the new weekly grid

#### Scenario: Refresh keyed by persistentModelID for row recycling

- **WHEN** the bound `Budget` value changes identity (e.g. navigating away and back to a different budget that recycles the view)
- **THEN** the `.task(id:)` is re-run so the lifecycle is computed for the new budget
