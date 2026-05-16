## ADDED Requirements

### Requirement: Row renders paused presentation when budget lifecycle state is paused

When `BudgetLifecycleResult.lifecycleState == .paused` for the budget rendered by a row, the row SHALL apply a paused visual treatment to the lifecycle-driven values:

- The `remaining` amount label SHALL render with `.foregroundStyle(.secondary)` (the greyed value treatment) regardless of sign, overriding the default surplus / deficit color rules.
- The `RemainingBar` SHALL render with `.foregroundStyle(.secondary)` (overriding accent / `Color.moneyDeficit` tints).
- When `Budget.isCarryOverEnabled == true` (so the `CarryOverChip` is rendered per the existing carry-over-chip requirement), the chip's value foreground style SHALL be overridden to `.secondary`; its background capsule tint SHALL remain its existing surplus / deficit color (so the chip stays visually identifiable as a carry-over chip).
- Below the row's primary content area (name / amount / period / bar), the row SHALL render a single line of `.caption`/`.secondary` text containing the localized caption `chip.paused.caption.format` (en-US "Paused since %@") using `BudgetLifecycleResult.pausedSince` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`. When `pausedSince` is `nil` (defensive — should not happen when `lifecycleState == .paused`), the caption SHALL be omitted.
- The row's composed VoiceOver label SHALL use a paused-state key (`budget.row.accessibilityLabel.paused`) that includes the budget's name, the formatted remaining amount, the inline period name, and the formatted `pausedSince` date. This is a distinct key from the existing on-budget / over-budget keys.

When `BudgetLifecycleResult.lifecycleState != .paused`, none of the paused-state treatments above SHALL apply; the row renders per the original requirements.

The paused presentation SHALL NOT affect the row's drill-in tap target, the per-row Add Expense button, or the swipe / reorder affordances. The user can still drill into a paused budget's detail screen, add an expense to it from the row's `plus.circle.fill` button (which presents `SheetRoute.addExpense(budget)` regardless of pause state — the date-bounds constraint lives in the Add/Edit Expense screen), and reorder the row.

#### Scenario: Paused row renders greyed value, greyed bar, and "Paused since" caption

- **WHEN** the lifecycle service returns `lifecycleState == .paused`, `remaining = 7.50`, and `pausedSince = 2026-05-01` for the budget rendered by a row
- **THEN** the row's `remaining` label and `RemainingBar` render with `.foregroundStyle(.secondary)`, and a `.caption`/`.secondary` line below the primary content reads "Paused since May 1, 2026"

#### Scenario: Paused carry-over chip stays visible with greyed value but tinted capsule

- **WHEN** `lifecycleState == .paused` and `Budget.isCarryOverEnabled == true`
- **THEN** the row's `CarryOverChip` continues to render with its formatted carry-over amount and its surplus / deficit background capsule color, but its value foreground style is overridden to `.secondary`

#### Scenario: Paused row VoiceOver label

- **WHEN** VoiceOver focuses a row whose budget is paused with `pausedSince = 2026-05-01`
- **THEN** the announced label uses key `budget.row.accessibilityLabel.paused` and includes the budget name, the formatted remaining amount, the inline period name, and "May 1, 2026"

#### Scenario: Paused row still supports row-level Add Expense

- **WHEN** the user taps the per-row `plus.circle.fill` button on a paused budget's row
- **THEN** `router.sheet = .addExpense(budget)` is set as it would be for an active budget (the Add/Edit Expense screen's date-bounds rules — see `add-edit-expense-screen` — handle the paused-state date constraint)

#### Scenario: Active row is unaffected by paused-state styling

- **WHEN** the lifecycle service returns `lifecycleState == .active` for the budget rendered by a row
- **THEN** the row renders per the original surplus / deficit color rules with no "Paused since" caption and no `.secondary` overrides
