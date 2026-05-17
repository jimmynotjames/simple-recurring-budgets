## ADDED Requirements

### Requirement: Add Expense surfaces a proactive paused note while budget is paused

When the bound budget's current `BudgetLifecycleResult.lifecycleState == .paused`, the Add/Edit Expense screen SHALL render a single proactive `.caption`/`.secondary` line directly below the When card explaining that backdated entries are permitted. The note SHALL use the localized key `addEditExpense.paused.caption.format` (en-US: *"Paused since %@. You can still add expenses dated before then."*) with the formatted `BudgetLifecycleResult.pausedSince` (locale-aware `Date.formatted(date: .abbreviated, time: .omitted)`).

The note SHALL be present for the entire lifetime of the sheet while the bound budget is paused — it is NOT gated on whether the user has tripped a date violation. It is intended as a proactive explainer for the paused-state affordance.

The note SHALL share its render slot with the existing `addEditExpense.date.outOfRange.caption` violation caption (see "Date picker bounds restrict the When field to the budget's active periods when paused"). When the picked date is inside a paused gap, the violation caption SHALL replace the proactive note in the same slot; the screen SHALL never render both captions stacked. The ViewModel SHALL expose a single computed property that returns the violation copy when the date is invalid, the proactive copy when the budget is paused and the date is valid, and `nil` otherwise.

The note SHALL NOT be rendered when `BudgetLifecycleResult.lifecycleState != .paused`. The pre-start (`now < startDate`) and post-end (`now > endDate`) clamped-default caption from F-2.04 SHALL take precedence over this note for budgets that are simultaneously pre-start or post-end (which by the moment-granular UI classification cannot happen — `.preStart` and `.postEnd` outrank `.paused` in `BudgetSnapshot.lifecycleState`), but the ordering MUST be defensive so that this rule holds even if a future change introduces overlapping states.

The note SHALL apply identically in Add mode and Edit mode. In Edit mode, the existing expense's date may already be inside an active period — the proactive note is still rendered while the bound budget is paused.

#### Scenario: Paused-budget Add Expense shows the proactive note at sheet open

- **WHEN** the user opens Add Expense for a daily budget whose `lifecycleState == .paused` with `pausedSince = 2026-05-10`
- **THEN** the `.caption`/`.secondary` line below the When card reads "Paused since May 10, 2026. You can still add expenses dated before then." and is visible from sheet appearance

#### Scenario: Proactive note persists across date edits within the valid range

- **WHEN** the user opens Add Expense for a paused budget, then changes the date to an earlier valid date inside an active interval
- **THEN** the proactive paused note continues to render in the same slot; no violation caption appears

#### Scenario: Violation caption replaces the proactive note in the same slot

- **WHEN** the user picks a date inside a paused gap (e.g., between two pause/resume cycles)
- **THEN** the proactive note is no longer rendered; instead the slot shows `addEditExpense.date.outOfRange.caption` ("Pick a date within an active period of this budget."), and Save is disabled. As soon as the user picks a date inside an active interval, the slot reverts to the proactive note and Save re-enables.

#### Scenario: Active-budget Add Expense shows no paused note

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState != .paused`
- **THEN** the proactive paused note is not rendered (the slot is empty unless an unrelated F-2.04 caption applies)

#### Scenario: Edit mode on paused budget shows the proactive note

- **WHEN** the user opens an existing `ExpenseItem` in Edit mode whose budget is currently paused, and the expense's `date` is inside a prior active period
- **THEN** the proactive paused note is rendered with the budget's `pausedSince` date; Save is enabled (because the existing date is valid)

## MODIFIED Requirements

### Requirement: Date picker bounds restrict the When field to the budget's active periods when paused

When the bound budget's current `BudgetLifecycleResult.lifecycleState == .paused`, the When (date / time) `DatePicker` SHALL constrain its accepted values to the union of the budget's active periods, computed from the budget's `LifecycleEvent` history.

The constraint SHALL be implemented in two stages:

1. **Picker range.** The `DatePicker` `in:` parameter SHALL be the closed range `[firstActivePeriodStart, pauseEffectiveDate]`, where:
   - `firstActivePeriodStart` is the `effectivePeriodStart` of the budget's earliest active period since `Budget.startDate` (falling back to `Budget.createdAt` if `startDate` is `nil`).
   - `pauseEffectiveDate` is the `effectiveDate` of the most recent `.pause` `LifecycleEvent` that is not followed by a later `.resume`. This is the precise upper bound — it explicitly permits **same-period-before-pause-moment** entries (e.g., the user paused at 11:00 today and can still log a coffee dated 09:00 today, because 09:00 lies inside the pause-action period and before the pause moment). It also implicitly inherits the math classifier's "pause-action period is active for math" rule.
   - When `Budget.endDate` is set, the upper bound SHALL additionally be clamped to `min(pauseEffectiveDate, endDate)`.
2. **Save-time validation.** When the user attempts to Save, the screen SHALL validate that the selected date lies inside one of the active-period intervals (not merely inside the bounding range above). If the selected date falls inside a paused gap (e.g., between two active intervals after multiple pause/resume cycles) or outside `[Budget.startDate, Budget.endDate]`, Save SHALL be blocked and the inline `.caption`/`.secondary` slot below the When card SHALL show the localized message `addEditExpense.date.outOfRange.caption` (en-US "Pick a date within an active period of this budget."), replacing the proactive paused note (see "Add Expense surfaces a proactive paused note while budget is paused"). Save SHALL become enabled again as soon as the user picks a date inside an active interval.

When `BudgetLifecycleResult.lifecycleState != .paused`, the date-bounds rule SHALL be the existing rule (no paused-state constraints introduced by this requirement). The pre-start (`now < startDate`) and post-end (`now > endDate`) clamping rules from F-2.04 apply independently and are not changed by this requirement.

The same two-stage validation SHALL apply in Add mode (the in-flight budget passed via `SheetRoute.addExpense(budget)`) and in Edit mode (`expense.budget`). In Edit mode, if the existing `expense.date` is outside the valid union (e.g., the user edits an expense from a since-paused budget whose date now sits inside a paused gap created by a later pause action), the picker SHALL load with its current value but Save SHALL be blocked with the same caption until the user picks a date inside an active interval, or until the user reverts the date to a value inside the active union.

The date seed for Add mode on a paused budget SHALL be `pauseEffectiveDate` (the most recent unbalanced `.pause` event's `effectiveDate`), guaranteeing that the initial value lies inside the active union and the picker does not open with an out-of-range default.

#### Scenario: Paused budget Add Expense restricts picker to active range with pause moment as upper bound

- **WHEN** the user opens Add Expense for a daily budget whose `startDate = 2026-04-01`, currently paused since `2026-05-10 14:00`
- **THEN** the When `DatePicker` accepts dates only in `[2026-04-01 00:00, 2026-05-10 14:00]`

#### Scenario: Same-period-before-pause-moment entry is allowed

- **WHEN** the user pauses a daily budget at 2026-05-10 11:00 and then opens Add Expense for that budget at 2026-05-10 11:05
- **THEN** the When `DatePicker` accepts a date of 2026-05-10 09:00 (same period, before the pause moment); Save is enabled when the user picks that date with a positive amount

#### Scenario: Active budget Add Expense uses the original date-bounds rule

- **WHEN** the user opens Add Expense for an active budget
- **THEN** the When `DatePicker` is NOT additionally constrained by this requirement; only the existing F-2.04 pre-start / post-end / `[startDate, endDate]` rules apply

#### Scenario: Save is blocked when the picked date sits inside a paused gap

- **WHEN** a budget has lifecycle history `[(.pause, 2026-04-10), (.resume, 2026-04-20), (.pause, 2026-05-01)]` and the user selects a date of 2026-04-15 in Add mode
- **THEN** Save is disabled, the inline caption `addEditExpense.date.outOfRange.caption` is shown directly below the When card (replacing the proactive paused note in the same slot), and the caption disappears (the proactive note returns and Save re-enables) as soon as the user picks a date inside one of the active intervals

#### Scenario: Edit mode loads an out-of-range existing date but blocks Save

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose `date` now sits inside a paused gap (created by a pause action after the expense was logged)
- **THEN** the When picker loads with the stored date, Save is disabled, and the inline caption `addEditExpense.date.outOfRange.caption` is shown until the user picks a date inside an active interval

#### Scenario: Save succeeds when picked date is inside the active union

- **WHEN** the user picks a date inside an active interval in either Add or Edit mode
- **THEN** Save is enabled, no inline out-of-range caption is shown, and on activation the screen persists the `ExpenseItem` per the existing Save requirements
