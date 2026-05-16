## ADDED Requirements

### Requirement: Date picker bounds restrict the When field to the budget's active periods when paused

When the bound budget's current `BudgetLifecycleResult.lifecycleState == .paused`, the When (date / time) `DatePicker` SHALL constrain its accepted values to the union of the budget's active periods, computed from the budget's `LifecycleEvent` history via the same period-granular rules used by `LifecycleClassification.isActive(period:lifecycleEvents:)`.

The constraint SHALL be implemented in two stages:

1. **Picker range.** The `DatePicker` `in:` parameter SHALL be the closed range `[firstActivePeriodStart, lastActivePeriodEnd]`, where:
   - `firstActivePeriodStart` is the `effectivePeriodStart` of the budget's earliest active period since `Budget.startDate` (falling back to `Budget.createdAt` if `startDate` is `nil`).
   - `lastActivePeriodEnd` is the `effectivePeriodEnd` of the most recent active period that closed strictly before the most recent `.pause` `LifecycleEvent`'s `effectiveDate` (or the `.pause` `effectiveDate` itself when it lands inside an otherwise-active period — the pause-action period is itself active per the algorithm, so it counts).
   - When `Budget.endDate` is set, `lastActivePeriodEnd` SHALL additionally be clamped to `min(lastActivePeriodEnd, endDate)`.
2. **Save-time validation.** When the user attempts to Save, the screen SHALL validate that the selected date lies inside one of the active-period intervals (not merely inside the bounding range above). If the selected date falls inside a paused gap (e.g., between two active intervals after multiple pause/resume cycles) or outside `[Budget.startDate, Budget.endDate]`, Save SHALL be blocked and an inline `.caption`/`.secondary` line SHALL appear directly below the When card with the localized message `addEditExpense.date.outOfRange.caption` (en-US "Pick a date within an active period of this budget."). Save SHALL become enabled again as soon as the user picks a date inside an active interval.

When `BudgetLifecycleResult.lifecycleState != .paused`, the date-bounds rule SHALL be the existing rule (no paused-state constraints introduced by this requirement). The pre-start (`now < startDate`) and post-end (`now > endDate`) clamping rules from F-2.04 apply independently and are not changed by this requirement.

The same two-stage validation SHALL apply in Add mode (the in-flight budget passed via `SheetRoute.addExpense(budget)`) and in Edit mode (`expense.budget`). In Edit mode, if the existing `expense.date` is outside the valid union (e.g., the user edits an expense from a since-paused budget whose date now sits inside a paused gap created by a later pause action), the picker SHALL load with its current value but Save SHALL be blocked with the same caption until the user picks a date inside an active interval, or until the user reverts the date to a value inside the active union.

#### Scenario: Paused budget Add Expense restricts picker to active range

- **WHEN** the user opens Add Expense for a daily budget whose `startDate = 2026-04-01`, currently paused since `2026-05-10`
- **THEN** the When `DatePicker` accepts dates only in `[2026-04-01 00:00, 2026-05-10 23:59]` (the union of active periods, where the pause-action day itself is active)

#### Scenario: Active budget Add Expense uses the original date-bounds rule

- **WHEN** the user opens Add Expense for an active budget
- **THEN** the When `DatePicker` is NOT additionally constrained by this requirement; only the existing F-2.04 pre-start / post-end / `[startDate, endDate]` rules apply

#### Scenario: Save is blocked when the picked date sits inside a paused gap

- **WHEN** a budget has lifecycle history `[(.pause, 2026-04-10), (.resume, 2026-04-20), (.pause, 2026-05-01)]` and the user selects a date of 2026-04-15 in Add mode
- **THEN** Save is disabled, the inline caption `addEditExpense.date.outOfRange.caption` is shown directly below the When card, and the caption disappears as soon as the user picks a date inside one of the active intervals

#### Scenario: Edit mode loads an out-of-range existing date but blocks Save

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose `date` now sits inside a paused gap (created by a pause action after the expense was logged)
- **THEN** the When picker loads with the stored date, Save is disabled, and the inline caption `addEditExpense.date.outOfRange.caption` is shown until the user picks a date inside an active interval

#### Scenario: Save succeeds when picked date is inside the active union

- **WHEN** the user picks a date inside an active interval in either Add or Edit mode
- **THEN** Save is enabled, no inline out-of-range caption is shown, and on activation the screen persists the `ExpenseItem` per the existing Save requirements
