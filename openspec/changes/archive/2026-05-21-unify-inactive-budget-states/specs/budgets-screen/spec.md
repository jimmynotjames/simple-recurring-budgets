## RENAMED Requirements

- FROM: `### Requirement: Row renders paused presentation when budget lifecycle state is paused`
- TO: `### Requirement: Row renders inactive presentation when budget lifecycle state is preStart, paused, or postEnd`

## MODIFIED Requirements

### Requirement: Row renders inactive presentation when budget lifecycle state is preStart, paused, or postEnd

When `BudgetLifecycleResult.lifecycleState` for the budget rendered by a row is any of `.preStart`, `.paused`, or `.postEnd` (collectively, the "inactive" states), the row SHALL apply a single unified visual treatment driven by a view-layer `BudgetInactiveReason` value derived from the lifecycle result and the budget. The reason carries the date payload used by the chip (`.preStart(startDate:)`, `.paused(since:)`, `.postEnd(endDate:)`). When `lifecycleState == .active`, `BudgetInactiveReason` is `nil` and none of the treatments below apply.

The inactive presentation SHALL be:

- **Amount label.** When the reason is `.preStart` or `.postEnd`, the amount label SHALL display the budget's `currentAllocation` (not `BudgetLifecycleResult.remaining`). When the reason is `.paused`, the label SHALL display `BudgetLifecycleResult.remaining`. In both cases the label SHALL use `.foregroundStyle(.secondary)` (the greyed value treatment), overriding the default surplus / deficit color rules. The deficit color SHALL NOT apply while inactive (allocation is always ≥ 0; paused remaining is greyed regardless of sign).
- **RemainingBar.** When `BudgetInactiveReason != nil`, the `RemainingBar` SHALL render as a full-width `.secondary`-filled capsule, regardless of the underlying `remainingFraction` / `isOverBudget` inputs.
- **CarryOverChip.** When `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates` (so the chip is rendered per the existing carry-over-chip requirement), the chip's value foreground style SHALL be overridden to `.secondary`; its background capsule tint SHALL remain its existing surplus / deficit color (so the chip stays visually identifiable as a carry-over chip). Backdated edits to prior active periods MAY still change the chip's value; the chip re-renders in the inactive presentation.
- **InactiveStatusChip.** The row SHALL render an `InactiveStatusChip` carrying the reason in the row's status chip area (the same area that previously rendered `PausedChip`). The chip SHALL be a sibling of (not nested inside) the row's drill-in button and SHALL carry the static-text accessibility trait. The chip's content SHALL vary by reason:
  - `.preStart(startDate:)` → SF Symbol `calendar.badge.clock` + localized label `chip.inactive.preStart.label.format` (en-US "Starts %@") with `startDate` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
  - `.paused(since:)` → SF Symbol `pause.circle.fill` + localized label `chip.paused.label.format` (en-US "Paused · %@") with `since` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`. *(Existing key reused; no copy change.)*
  - `.postEnd(endDate:)` → SF Symbol `checkmark.circle` + localized label `chip.inactive.postEnd.label.format` (en-US "Ended %@") with `endDate` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
  - All three variants share capsule styling: `.font(.caption)`, `.fontWeight(.medium)`, `.foregroundStyle(.secondary)`, horizontal/vertical padding scaled with Dynamic Type, `Capsule().fill(Color.primary.opacity(0.15))` (or `0.05` under increased contrast).
- **VoiceOver label (row).** The row's composed VoiceOver label is produced by `BudgetRemainingSummary.accessibilityLabel(...)`. This change extends that helper to take the `BudgetInactiveReason?` and dispatch to two new keys for the preStart and postEnd cases (the paused case continues to use the existing on-budget / over-budget keys, matching today's behavior — closing the paused-label gap is out of scope for this change):
  - `.preStart` → key `budget.summary.accessibilityLabel.preStart` (en-US body "%@ %@ starts %@" where args are amount, periodInlineLabel, startDate; the budget name is prepended by the caller via the existing `withName` Swift-side prefix pattern).
  - `.paused` → existing keys `budget.summary.accessibilityLabel` / `.overBudget` reused unchanged.
  - `.postEnd` → key `budget.summary.accessibilityLabel.postEnd` (en-US body "%@ %@ ended %@" where args are amount, periodInlineLabel, endDate; budget name prepended by caller).
- **VoiceOver label (chip).** The `InactiveStatusChip` SHALL provide its own static-text accessibility label per reason:
  - `.preStart` → key `chip.inactive.preStart.accessibilityLabel.format` (en-US "Starts %@").
  - `.paused` → key `chip.paused.accessibilityLabel.format` (existing key reused — en-US "Paused since %@").
  - `.postEnd` → key `chip.inactive.postEnd.accessibilityLabel.format` (en-US "Ended %@").

The inactive presentation SHALL NOT affect the row's drill-in tap target, the per-row Add Expense button, or the swipe / reorder affordances. The user can still drill into an inactive budget's detail screen, add an expense to it from the row's `plus.circle.fill` button (which presents `SheetRoute.addExpense(budget)` regardless of lifecycle state — the date-bounds constraint lives in the Add/Edit Expense screen), and reorder the row.

Specific Dates budgets (`Budget.period == .specificDates`) viewed before `startDate` or after `endDate` SHALL receive the same `.preStart` / `.postEnd` treatment as recurring budgets (same chip, same copy, same allocation-as-amount choice). Specific Dates budgets cannot be `.paused` per F-2.08, so the `.paused` variant never fires for them.

#### Scenario: Paused row renders greyed remaining, full-width secondary bar, and Paused chip

- **WHEN** the lifecycle service returns `lifecycleState == .paused`, `remaining = 7.50`, and `pausedSince = 2026-05-01` for the budget rendered by a row
- **THEN** the row's amount label displays `7.50` with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Paused · May 1, 2026" appears in the row's status chip area

#### Scenario: Pre-start row renders greyed allocation, full-width secondary bar, and Starts chip

- **WHEN** the lifecycle service returns `lifecycleState == .preStart` for a daily budget whose `startDate = 2026-06-01` and `currentAllocation = 25.00`
- **THEN** the row's amount label displays `25.00` (the allocation, not `remaining`) with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Starts Jun 1, 2026" appears in the row's status chip area

#### Scenario: Post-end row renders greyed allocation, full-width secondary bar, and Ended chip

- **WHEN** the lifecycle service returns `lifecycleState == .postEnd` for a monthly budget whose `endDate = 2026-04-10` and `currentAllocation = 400.00`
- **THEN** the row's amount label displays `400.00` (the allocation, not the final period's residual `remaining`) with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Ended Apr 10, 2026" appears in the row's status chip area

#### Scenario: Inactive carry-over chip stays visible with greyed value but tinted capsule

- **WHEN** `BudgetInactiveReason != nil` (any of `.preStart`, `.paused`, `.postEnd`) AND `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`
- **THEN** the row's `CarryOverChip` continues to render with its formatted carry-over amount and its surplus / deficit background capsule color, but its value foreground style is overridden to `.secondary`

#### Scenario: Inactive presentation does not apply to Specific Dates carry-over chip

- **WHEN** `BudgetInactiveReason != nil` AND `Budget.period == .specificDates`
- **THEN** the `CarryOverChip` is omitted entirely (per F-2.08, regardless of the inactive presentation), and only the `InactiveStatusChip` appears in the row's status chip area

#### Scenario: Specific Dates pre-window row renders Starts chip

- **WHEN** the lifecycle service returns `lifecycleState == .preStart` for a `.specificDates` budget whose `startDate = 2026-07-15`
- **THEN** the row renders the inactive treatment with an `InactiveStatusChip` reading "Starts Jul 15, 2026" and no `CarryOverChip`

#### Scenario: Specific Dates post-window row renders Ended chip

- **WHEN** the lifecycle service returns `lifecycleState == .postEnd` for a `.specificDates` budget whose `endDate = 2026-03-31`
- **THEN** the row renders the inactive treatment with an `InactiveStatusChip` reading "Ended Mar 31, 2026" and no `CarryOverChip`

#### Scenario: Paused row VoiceOver label uses existing on-budget / over-budget keys

- **WHEN** VoiceOver focuses a row whose budget is paused
- **THEN** the announced label uses the existing `budget.summary.accessibilityLabel` (or `.overBudget` for negative remaining) key — the paused-state suffix is not introduced by this change

#### Scenario: Pre-start row VoiceOver label

- **WHEN** VoiceOver focuses a row whose budget is `.preStart` with `startDate = 2026-06-01`
- **THEN** the announced label uses key `budget.summary.accessibilityLabel.preStart` and includes the budget name (Swift-side prefix), the formatted allocation amount, the inline period name, and "Jun 1, 2026"

#### Scenario: Post-end row VoiceOver label

- **WHEN** VoiceOver focuses a row whose budget is `.postEnd` with `endDate = 2026-04-10`
- **THEN** the announced label uses key `budget.summary.accessibilityLabel.postEnd` and includes the budget name (Swift-side prefix), the formatted allocation amount, the inline period name, and "Apr 10, 2026"

#### Scenario: Inactive row still supports row-level Add Expense

- **WHEN** the user taps the per-row `plus.circle.fill` button on a row whose budget is in any inactive lifecycle state (`.preStart`, `.paused`, or `.postEnd`)
- **THEN** `router.sheet = .addExpense(budget)` is set as it would be for an active budget (the Add/Edit Expense screen's date-bounds rules — see `add-edit-expense-screen` — handle the lifecycle-state date constraint)

#### Scenario: Active row is unaffected by inactive-state styling

- **WHEN** the lifecycle service returns `lifecycleState == .active` for the budget rendered by a row
- **THEN** the row renders per the original surplus / deficit color rules with no `InactiveStatusChip`, no `.secondary` overrides, and a fraction-driven `RemainingBar`
