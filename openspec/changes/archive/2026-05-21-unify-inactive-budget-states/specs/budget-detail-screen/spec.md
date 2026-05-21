## RENAMED Requirements

- FROM: `### Requirement: Status header renders paused presentation when lifecycle state is paused`
- TO: `### Requirement: Status header renders inactive presentation when lifecycle state is preStart, paused, or postEnd`

## MODIFIED Requirements

### Requirement: Status header renders inactive presentation when lifecycle state is preStart, paused, or postEnd

When `BudgetLifecycleResult.lifecycleState` is any of `.preStart`, `.paused`, or `.postEnd` (collectively, the "inactive" states), the status header SHALL render its values with a single unified visual treatment driven by a view-layer `BudgetInactiveReason` value derived from the lifecycle result and the budget. The reason carries the date payload used by the chip (`.preStart(startDate:)`, `.paused(since:)`, `.postEnd(endDate:)`). When `lifecycleState == .active`, `BudgetInactiveReason` is `nil` and none of the treatments below apply.

The inactive presentation SHALL be:

- **Large amount label.** When the reason is `.preStart` or `.postEnd`, the large amount label SHALL display the budget's `currentAllocation` (not `BudgetLifecycleResult.remaining`). When the reason is `.paused`, the label SHALL display `BudgetLifecycleResult.remaining`. In both cases the label SHALL use `.foregroundStyle(.secondary)` (the greyed value treatment), overriding the default primary-text / `Color.moneyDeficit` rules for non-inactive states.
- **RemainingBar.** When `BudgetInactiveReason != nil`, the `RemainingBar` SHALL render as a full-width `.secondary`-filled capsule, regardless of the underlying `remainingFraction` / `isOverBudget` inputs.
- **CarryOverChip.** When `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`, the `CarryOverChip` SHALL continue to render with its formatted carry-over amount, but its foreground style SHALL be overridden to `.secondary` while its background tint remains its existing surplus / deficit color. The chip's value SHALL remain live — backdated edits to prior active periods MAY still change it.
- **InactiveStatusChip.** The header SHALL render an `InactiveStatusChip` carrying the reason in the status chip area (the same area that previously rendered `PausedChip`). The chip's content SHALL vary by reason:
  - `.preStart(startDate:)` → SF Symbol `calendar.badge.clock` + localized label `chip.inactive.preStart.label.format` (en-US "Starts %@") with `startDate` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
  - `.paused(since:)` → SF Symbol `pause.circle.fill` + localized label `chip.paused.label.format` (en-US "Paused · %@") with `since` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`. *(Existing key reused; no copy change.)*
  - `.postEnd(endDate:)` → SF Symbol `checkmark.circle` + localized label `chip.inactive.postEnd.label.format` (en-US "Ended %@") with `endDate` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
  - All three variants share capsule styling identical to the corresponding `budgets-screen` chip requirement (`.font(.caption)`, `.fontWeight(.medium)`, `.foregroundStyle(.secondary)`, Dynamic-Type-scaled padding, `Capsule().fill(Color.primary.opacity(0.15))` with `0.05` under increased contrast).
- **VoiceOver label (header).** The header's composed VoiceOver label is produced by the same `BudgetRemainingSummary.accessibilityLabel(...)` helper used by the Budgets-list row, with `budgetName: nil` since the nav title already announces the budget name. This change extends that helper to dispatch to two new keys for the preStart and postEnd cases (the paused case continues to use the existing on-budget / over-budget keys, matching today's behavior):
  - `.preStart` → key `budget.summary.accessibilityLabel.preStart` (en-US body "%@ %@ starts %@" where args are amount, periodInlineLabel, startDate).
  - `.paused` → existing keys `budget.summary.accessibilityLabel` / `.overBudget` reused unchanged.
  - `.postEnd` → key `budget.summary.accessibilityLabel.postEnd` (en-US body "%@ %@ ended %@" where args are amount, periodInlineLabel, endDate).
- **VoiceOver label (chip).** The `InactiveStatusChip` SHALL provide its own static-text accessibility label per reason, using the same keys as the `budgets-screen` requirement (`chip.inactive.preStart.accessibilityLabel.format`, `chip.paused.accessibilityLabel.format`, `chip.inactive.postEnd.accessibilityLabel.format`).

The inactive presentation SHALL NOT affect the primary action slot (which retains its existing state-driven behavior — Add Expense for `.active`/`.preStart`/`.postEnd`, Resume Budget for `.paused`), the toolbar overflow Menu's action gating (which continues to consume `lifecycleState` directly), or the expense list section.

Specific Dates budgets (`Budget.period == .specificDates`) viewed before `startDate` or after `endDate` SHALL receive the same `.preStart` / `.postEnd` treatment as recurring budgets (same chip, same copy, same allocation-as-amount choice). Specific Dates budgets cannot be `.paused` per F-2.08, so the `.paused` variant never fires for them. The `CarryOverChip` is omitted for Specific Dates regardless of the inactive presentation (existing F-2.08 rule).

#### Scenario: Paused header renders greyed remaining, full-width secondary bar, and Paused chip

- **WHEN** the lifecycle service returns `lifecycleState == .paused`, `remaining = 7.50`, and `pausedSince = 2026-05-01`
- **THEN** the large amount label displays `7.50` with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Paused · May 1, 2026" appears in the header's chip area

#### Scenario: Pre-start header renders greyed allocation, full-width secondary bar, and Starts chip

- **WHEN** the lifecycle service returns `lifecycleState == .preStart` for a weekly budget whose `startDate = 2026-06-01` and `currentAllocation = 150.00`
- **THEN** the large amount label displays `150.00` (the allocation, not `remaining`) with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Starts Jun 1, 2026" appears in the header's chip area

#### Scenario: Post-end header renders greyed allocation, full-width secondary bar, and Ended chip

- **WHEN** the lifecycle service returns `lifecycleState == .postEnd` for a monthly budget whose `endDate = 2026-04-10` and `currentAllocation = 400.00`
- **THEN** the large amount label displays `400.00` (the allocation, not the final period's residual `remaining`) with `.foregroundStyle(.secondary)`, the `RemainingBar` renders as a full-width `.secondary`-filled capsule, and an `InactiveStatusChip` reading "Ended Apr 10, 2026" appears in the header's chip area

#### Scenario: Inactive carry-over chip stays visible but greyed

- **WHEN** `BudgetInactiveReason != nil` AND `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`
- **THEN** the `CarryOverChip` continues to render in the header with its formatted carry-over amount, but its foreground style is overridden to `.secondary` and its background tint is unchanged from active-state styling

#### Scenario: Paused chip value updates on backdated edits

- **WHEN** the budget is paused and the user edits an `ExpenseItem` whose `date` falls inside a prior active period
- **THEN** the next `BudgetLifecycleService.result(for:)` call returns the recomputed `carryOverAmount` and the header chip re-renders with the new value (still in the paused inactive presentation)

#### Scenario: Paused header VoiceOver label uses existing on-budget / over-budget keys

- **WHEN** VoiceOver focuses the header in the `.paused` state
- **THEN** the announced label uses the existing `budget.summary.accessibilityLabel` (or `.overBudget` for negative remaining) key — the paused-state suffix is not introduced by this change

#### Scenario: Pre-start header VoiceOver label

- **WHEN** VoiceOver focuses the header in the `.preStart` state with `startDate = 2026-06-01`
- **THEN** the announced label uses key `budget.summary.accessibilityLabel.preStart` and includes the formatted allocation amount, the inline period name, and "Jun 1, 2026"

#### Scenario: Post-end header VoiceOver label

- **WHEN** VoiceOver focuses the header in the `.postEnd` state with `endDate = 2026-04-10`
- **THEN** the announced label uses key `budget.summary.accessibilityLabel.postEnd` and includes the formatted allocation amount, the inline period name, and "Apr 10, 2026"

#### Scenario: Active header is unaffected by inactive-state styling

- **WHEN** the lifecycle service returns `lifecycleState == .active`
- **THEN** the header renders per the original primary-text / `Color.moneyDeficit` rules with no `InactiveStatusChip`, no `.secondary` overrides, and a fraction-driven `RemainingBar`

#### Scenario: Inactive presentation does not change primary action slot behavior

- **WHEN** the lifecycle service returns `lifecycleState == .preStart` or `.postEnd`
- **THEN** the primary action slot continues to render the existing "Add Expense" button (no caption is added by this requirement; only the header presentation changes)
