## MODIFIED Requirements

### Requirement: Add mode seeds blank-amount, empty-description, current-date defaults

In Add mode, the form fields SHALL be initialised at sheet-open time as follows, all evaluated **once** when `AddEditExpenseViewModel.init(adding:)` runs:

- `amount = nil` (no default amount — the Amount field is blank until the user enters a positive value).
- `name = ""` (empty string — the Description `TextField` displays the placeholder; the persisted value is `nil` if the user does not type anything).
- `currencyCode = budget.currencyCode` (matches the parent budget's currency for the prefix display).
- `date` — seeded per the bound budget's `BudgetSnapshot.lifecycleState` at sheet-open time:
  - `.paused` (with a recoverable pause moment) → the most recent unbalanced `.pause` event's `effectiveDate` (guaranteed to lie inside the active union; matches the upper bound of `dateRange`).
  - `.postEnd` (with `budget.endDate` non-`nil`) → the last moment of `endDate`'s day (specifically `calendar.startOfDay(for: Date.addingTimeInterval(86400, to: startOfDay(endDate))) - 1` — i.e. the same upper-bound expression used by `dateRange` for post-end / specific-dates budgets). This guarantees the picker opens inside its allowed range; without this clamp the default would be `Date()` (now), which sits above the upper bound when `now > endDate`.
  - All other states (`.active`, `.preStart`, `.paused` without a recoverable pause moment) → `max(Date(), budget.effectiveStartDate)` (the existing rule — floor at the budget's start so a pre-start picker opens at the start date).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` or the parent `Budget` after the sheet opens; the user can edit any field manually before saving.

The `cachedStartDateFormatted` and `cachedEndDateFormatted` `String?` properties on the VM SHALL be populated only when the bound budget is `.preStart` (start) or `.postEnd` (end) at sheet-open time; they SHALL be `nil` otherwise. They are consumed by the `dateContextCaption` requirement.

#### Scenario: Add mode opens with documented defaults for an active budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `currencyCode == "USD"` whose lifecycle is `.active`
- **THEN** the form shows: amount field blank (draft `nil`), description field empty (placeholder visible), When picker at the current date and time, currency prefix derived from `"USD"` and the user's `currencyDisplay` preference; Save is disabled because `amount` is `nil`

#### Scenario: Add mode seeds date to pause moment for paused budget

- **WHEN** the sheet opens in Add mode for a paused budget with the most-recent unbalanced `.pause` event at `2026-05-10 14:00`
- **THEN** the seeded `date` equals `2026-05-10 14:00`

#### Scenario: Add mode seeds date to endDate end-of-day for post-end budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `endDate == 2026-04-15` whose lifecycle is `.postEnd`
- **THEN** the seeded `date` equals the last moment of `2026-04-15` (i.e. `2026-04-15 23:59:59`), guaranteeing the picker opens inside `dateRange`'s `[effectiveStartDate, endDate-end-of-day]` window

#### Scenario: Add mode seeds date to effectiveStartDate for pre-start budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `startDate == 2026-06-01` whose lifecycle is `.preStart` (`now < startDate`)
- **THEN** the seeded `date` equals `2026-06-01 00:00` (i.e. `max(Date(), budget.effectiveStartDate)`, which collapses to `effectiveStartDate` when `Date()` is earlier)

### Requirement: Add Expense surfaces a proactive paused note while budget is paused

The Add/Edit Expense screen SHALL render at most one inline caption (`.font(.caption)` / `.foregroundStyle(.secondary)`) directly below the When card, resolved at body-evaluation time from the bound budget's lifecycle state via a single VM property `dateContextCaption: String?`. The view SHALL NOT render any caption when this property returns `nil`.

The caption is resolved in priority order. The screen SHALL never render two captions stacked.

1. **Paused + date out of range.** When `cachedBudgetSnapshot?.lifecycleState == .paused` AND the picked `date` falls outside the active union (per the "Date picker bounds restrict the When field to the budget's active periods when paused" requirement), the caption SHALL be the localized string keyed `addEditExpense.date.outOfRange.caption` (en-US: *"Pick a date within an active period of this budget."*).
2. **Paused + date valid.** When `cachedBudgetSnapshot?.lifecycleState == .paused` AND the picked `date` lies inside the active union AND a `pauseEffectiveDate` is recoverable, the caption SHALL be the localized key `addEditExpense.paused.caption.format` (en-US: *"Paused since %@. You can still add expenses dated before then."*) with the formatted `pauseEffectiveDate` (locale-aware `Date.formatted(date: .abbreviated, time: .omitted)`). This is the proactive paused note.
3. **Add mode + pre-start.** When the VM is in Add mode (`isEditing == false`) AND `cachedBudgetSnapshot?.lifecycleState == .preStart` AND `cachedStartDateFormatted` is non-`nil`, the caption SHALL be the localized key `addEditExpense.preStart.caption.format` (en-US: *"Budget starts on %@."*) with `cachedStartDateFormatted`. (Per F-2.04.)
4. **Add mode + post-end.** When the VM is in Add mode AND `cachedBudgetSnapshot?.lifecycleState == .postEnd` AND `cachedEndDateFormatted` is non-`nil`, the caption SHALL be the localized key `addEditExpense.postEnd.caption.format` (en-US: *"Budget ended on %@."*) with `cachedEndDateFormatted`. (Per F-2.04.)
5. **Otherwise** the property SHALL return `nil` (active budget in Add mode, any state in Edit mode that doesn't match the paused branches, etc.).

Edit-mode pre-start / post-end captions are intentionally suppressed (Add-mode-only per F-2.04): an existing `ExpenseItem` already carries its stored date, so the clamped-default rationale doesn't apply.

The paused branches (priority 1 and 2) apply in BOTH Add mode and Edit mode — these are about explaining the date-bounds constraint, which still applies in Edit mode when the bound budget is paused.

The pre-start and post-end captions SHALL persist for the entire lifetime of the sheet while the budget is in that lifecycle state — they are NOT gated on whether the picker still shows the clamped default — since the underlying `[startDate, endDate]` constraint still applies after the user edits the field.

#### Scenario: Paused-budget Add Expense shows the proactive note at sheet open

- **WHEN** the user opens Add Expense for a daily budget whose `lifecycleState == .paused` with `pauseEffectiveDate == 2026-05-10`
- **THEN** the `.caption`/`.secondary` line below the When card reads "Paused since May 10, 2026. You can still add expenses dated before then." and is visible from sheet appearance

#### Scenario: Proactive note persists across date edits within the valid range

- **WHEN** the user opens Add Expense for a paused budget, then changes the date to an earlier valid date inside an active interval
- **THEN** the proactive paused note continues to render in the same slot; no violation caption appears

#### Scenario: Violation caption replaces the proactive note in the same slot

- **WHEN** the user picks a date inside a paused gap (e.g., between two pause/resume cycles)
- **THEN** the proactive note is no longer rendered; instead the slot shows `addEditExpense.date.outOfRange.caption` ("Pick a date within an active period of this budget."), and Save is disabled. As soon as the user picks a date inside an active interval, the slot reverts to the proactive note and Save re-enables.

#### Scenario: Active-budget Add Expense shows no caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .active`
- **THEN** `dateContextCaption` returns `nil` and no caption is rendered

#### Scenario: Edit mode on paused budget shows the proactive note

- **WHEN** the user opens an existing `ExpenseItem` in Edit mode whose budget is currently paused, and the expense's `date` is inside a prior active period
- **THEN** the proactive paused note is rendered with the budget's `pauseEffectiveDate`; Save is enabled (because the existing date is valid)

#### Scenario: Add mode on pre-start budget shows the pre-start caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .preStart` with `startDate == 2026-06-01`
- **THEN** the caption below the When card reads "Budget starts on Jun 1, 2026." (key `addEditExpense.preStart.caption.format`) for the lifetime of the sheet, irrespective of whether the user changes the picked date

#### Scenario: Add mode on post-end budget shows the post-end caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .postEnd` with `endDate == 2026-04-15`
- **THEN** the caption below the When card reads "Budget ended on Apr 15, 2026." (key `addEditExpense.postEnd.caption.format`) for the lifetime of the sheet

#### Scenario: Edit mode on pre-start budget shows no pre-start caption

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose budget is `.preStart`
- **THEN** the pre-start caption is NOT rendered (Add-mode-only per F-2.04); the existing expense's stored date already accommodates the bounds

#### Scenario: Edit mode on post-end budget shows no post-end caption

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose budget is `.postEnd`
- **THEN** the post-end caption is NOT rendered (Add-mode-only per F-2.04)

#### Scenario: Paused state outranks pre-start / post-end in caption priority

- **WHEN** a hypothetical lifecycle classification reported `.paused` simultaneously with `.preStart` (which the moment-granular UI classifier prevents in practice)
- **THEN** the paused caption (priority 1 or 2) is rendered, not the pre-start or post-end caption — the priority ordering is defensive against future overlapping-state changes
