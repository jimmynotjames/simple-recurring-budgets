## MODIFIED Requirements

### Requirement: Status header presents remaining, period, RemainingBar, and conditional carry-over chip

The first List section SHALL be a status header showing:

- The current-period **remaining** amount, formatted with the budget's `currencyCode` and `AppSettings.currencyDisplay`, rendered in the system large-title font with `monospacedDigit()`. When remaining is negative, the amount SHALL be tinted with `Color.moneyDeficit`; when zero or positive, the primary text color.
- The period label sourced from `Budget.periodDisplayLabel` rendered in the system callout font with secondary foreground. For recurring periods this resolves to "Daily" / "Weekly" / "Biweekly" / "Monthly" (via `BudgetPeriod.listLabel`). For `.specificDates` budgets this resolves to the formatted date range produced by `Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)` over `Budget.startDate ..< Budget.endDate`. See `data-models` for the `Budget.periodDisplayLabel` definition.
- A `RemainingBar` decorative bar bound to `clamp(remaining / allocation, 0, 1)`, hidden from VoiceOver and following the same on-budget vs over-budget rules as the Budgets row (accent fill when remaining ≥ 0; full deficit fill when remaining < 0; empty when allocation is 0).
- When `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`, a row beneath the bar containing a `CarryOverChip` (passing `lifecycle?.carryOverAmount ?? 0`, `currencyCode`, and `AppSettings.currencyDisplay`). The header SHALL NOT render any trailing action control on this row — the manual carry-over reset trigger lives in the toolbar overflow Menu (see the separate "Toolbar overflow Menu" requirement below). When `isCarryOverEnabled == false` OR `period == .specificDates`, this row SHALL be omitted entirely (per F-2.08, the Carry-Over chip is hidden for Specific Dates budgets regardless of the stored `isCarryOverEnabled` value).

The header SHALL collapse the amount and period label into a single accessibility element with the composed VoiceOver label specified by the dedicated requirement below.

The header's amount + period container SHALL use `ViewThatFits(in: .horizontal)` so the layout responds to actual content width rather than a fixed `dynamicTypeSize` threshold. The first (preferred) child SHALL be a horizontal `HStack(alignment: .firstTextBaseline, spacing: amountSpacing)` containing the amount text and the period label, both with `.lineLimit(1)` so `ViewThatFits` correctly detects overflow. The fallback child SHALL be a vertical `VStack(alignment: .leading, spacing: amountSpacing)` containing the same two texts; in this fallback the period label SHALL omit `.lineLimit(1)` so it can wrap naturally on its own line. Row spacing, amount-stack spacing, chip top spacing, and row vertical padding SHALL scale via `@ScaledMetric` relative to the relevant text style.

This requirement explicitly replaces the prior fixed-threshold behaviour (HStack below `.xxxLarge`, VStack at `.xxxLarge` and above). The `ViewThatFits` approach handles both font-size scaling and content-width changes (notably the longer date-range label produced for `.specificDates` budgets) in a single rule.

The header section SHALL set `listRowBackground(Color("CellBackground"))` and hide the row separator.

#### Scenario: Positive remaining renders with primary color

- **WHEN** the lifecycle service returns `remaining >= 0` for the budget
- **THEN** the amount text uses the primary text color and the period label uses the secondary text color

#### Scenario: Negative remaining renders in deficit color

- **WHEN** the lifecycle service returns `remaining < 0` for the budget
- **THEN** the amount text uses `Color.moneyDeficit` and the `RemainingBar` fills 100% of its width in `Color.moneyDeficit`

#### Scenario: Recurring period label uses BudgetPeriod.listLabel

- **WHEN** the header is rendered for a budget with period `.weekly`
- **THEN** the period label renders the localized string "Weekly" (key `period.weekly`)

#### Scenario: Specific Dates period label renders as a date range

- **WHEN** the header is rendered for a `.specificDates` budget with `startDate = 2026-05-08` and `endDate = 2026-05-25` and the user's locale is en-US
- **THEN** the period label renders "May 8 – May 25"

#### Scenario: Carry-over chip omitted when toggle is off

- **WHEN** `Budget.isCarryOverEnabled == false`
- **THEN** the header SHALL NOT render the carry-over chip row, regardless of the underlying `carryOverAmount` value

#### Scenario: Carry-over chip omitted for Specific Dates regardless of stored toggle

- **WHEN** `Budget.period == .specificDates` AND `Budget.isCarryOverEnabled == true` (e.g., a record arriving via CloudKit before this change shipped)
- **THEN** the header SHALL NOT render the carry-over chip row; `.specificDates` budgets never display the chip on this screen

#### Scenario: Carry-over row visible when toggle is on and period is recurring

- **WHEN** `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`
- **THEN** the header renders a `CarryOverChip` on a row beneath the `RemainingBar`, with no trailing action button in the header; the manual carry-over reset is triggered exclusively from the toolbar overflow Menu

#### Scenario: Header carry-over row is unaffected by the live carry-over magnitude

- **WHEN** `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates` AND the live `carryOverAmount` is zero, positive, or negative
- **THEN** the header carry-over row renders in all three cases; the row's visibility depends only on `isCarryOverEnabled` and `period`, not on the magnitude or sign of `carryOverAmount`

#### Scenario: Horizontal layout when content fits

- **WHEN** the amount and period label together fit within the available header width at their ideal one-line size
- **THEN** the layout uses the HStack child with both texts side-by-side aligned to the first text baseline

#### Scenario: Vertical layout when content does not fit

- **WHEN** the amount and period label together exceed the available header width (e.g. at larger Dynamic Type sizes, or for a long `.specificDates` date-range label)
- **THEN** `ViewThatFits` selects the VStack child, rendering the amount above the period label aligned to the leading edge

### Requirement: Toolbar overflow Menu hosts Edit Budget and Reset Budget actions

The screen SHALL place a single `topBarTrailing` toolbar item rendered as a `Menu` whose label is the SF Symbol `ellipsis.circle`. The Menu SHALL contain, in order:

1. **Edit Budget** (key `budgetDetail.menu.editBudget`, system image `pencil`) — activating it sets `router.sheet = .editBudget(budget)`. Visible in every lifecycle state.
2. **Pause Budget** / **Resume Budget** (state-driven; see below).
3. A `Divider`.
4. **Reset Carry-Over…** (key `budgetDetail.menu.resetCarryOver`, system image `arrow.counterclockwise.circle`, `role: .destructive`) — activating it triggers the Reset Carry-Over confirmation flow. Visible only when `Budget.isCarryOverEnabled == true` AND `Budget.period != .specificDates`; omitted entirely otherwise (per F-2.08, Reset Carry-Over is hidden for Specific Dates budgets). Visible in every lifecycle state in which the screen is rendered, regardless of the live carry-over balance's magnitude or sign.
5. **Reset Budget…** (key `budgetDetail.menu.resetBudget`, system image `arrow.counterclockwise`, `role: .destructive`) — activating it triggers the Reset Budget confirmation flow.

The Pause/Resume item SHALL be:

- **Hidden** when `BudgetPeriod(rawValue: budget.period) == .specificDates` (Specific Dates budgets are not pausable per `docs/product-features-planning.md` F-2.08).
- **Hidden** when `BudgetLifecycleResult.lifecycleState == .postEnd` (a terminal budget cannot be paused or resumed per F-7.07).
- Otherwise, **visible** with state-driven label and icon:
  - When `lifecycleState == .active` or `.preStart`: the item reads "Pause Budget" (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`). Activating it calls `BudgetLifecycleService.pauseBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fires the `budget_paused` analytics event and re-invokes `BudgetLifecycleService.result(for:)`. No confirmation dialog is presented (pause is reversible).
  - When `lifecycleState == .paused`: the item reads "Resume Budget" (key `budgetDetail.menu.resumeBudget`, system image `play.circle`). Activating it performs the same Resume action as the primary action button.

The Menu SHALL provide a localized accessibility label (key `budgetDetail.menu.accessibilityLabel`). The Reset Carry-Over… menu item SHALL provide a localized accessibility hint (key `budgetDetail.menu.resetCarryOver.accessibilityHint`) whose en-US value is "Clears the carry-over balance to zero. Expenses are not affected." The Reset Budget… menu item SHALL provide a localized accessibility hint (key `budgetDetail.menu.resetBudget.accessibilityHint`) whose en-US value is "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused."

#### Scenario: Edit Budget opens the edit sheet

- **WHEN** the user taps the ellipsis Menu and selects Edit Budget
- **THEN** `router.sheet` is set to `SheetRoute.editBudget(budget)` and the Add/Edit Budget sheet opens in Edit mode for this budget

#### Scenario: Reset Carry-Over opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Carry-Over… on a recurring budget with `isCarryOverEnabled == true`
- **THEN** the Reset Carry-Over confirmation alert is presented

#### Scenario: Reset Budget opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Budget…
- **THEN** the Reset Budget confirmation dialog is presented

#### Scenario: Reset Carry-Over menu item is shown for recurring budgets with carry-over enabled

- **WHEN** the user opens the Menu on a recurring budget (any period other than `.specificDates`) with `Budget.isCarryOverEnabled == true`
- **THEN** the Menu contains a "Reset Carry-Over…" item positioned beneath the `Divider` and above the "Reset Budget…" item

#### Scenario: Reset Carry-Over menu item is omitted when carry-over is disabled

- **WHEN** the user opens the Menu on a recurring budget with `Budget.isCarryOverEnabled == false`
- **THEN** the Menu does NOT contain a "Reset Carry-Over…" item; the Divider is still present and Reset Budget… is still the only destructive item below it

#### Scenario: Reset Carry-Over menu item is omitted for Specific Dates budgets

- **WHEN** the user opens the Menu on a `.specificDates` budget (regardless of the stored `isCarryOverEnabled` value)
- **THEN** the Menu does NOT contain a "Reset Carry-Over…" item; the Divider is still present and Reset Budget… is the only destructive item below it

#### Scenario: Reset Carry-Over menu item is shown regardless of carry-over balance value

- **WHEN** the user opens the Menu on a recurring budget with `isCarryOverEnabled == true` and the live `carryOverAmount` is zero
- **THEN** the Reset Carry-Over… item is still present and selectable; visibility is gated only by `isCarryOverEnabled` and `period != .specificDates`, not by the current balance

#### Scenario: Pause item is shown for active recurring budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .active`
- **THEN** the Menu contains a "Pause Budget" item

#### Scenario: Resume item is shown for paused budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .paused`
- **THEN** the Menu contains a "Resume Budget" item

#### Scenario: Pause/Resume item is hidden for Specific Dates budgets

- **WHEN** the user opens the Menu on a `.specificDates` budget
- **THEN** the Menu contains Edit Budget and Reset Budget…, but no Pause Budget, Resume Budget, or Reset Carry-Over… item

#### Scenario: Pause/Resume item is hidden once budget is past endDate

- **WHEN** the user opens the Menu on a budget whose `endDate` has passed (`lifecycleState == .postEnd`) AND `period != .specificDates`
- **THEN** the Menu contains Edit Budget, optionally Reset Carry-Over…, and Reset Budget…, but no Pause Budget or Resume Budget item

#### Scenario: Tapping Pause writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on an active daily budget and taps "Pause Budget"
- **THEN** `BudgetLifecycleService.pauseBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_paused` analytics event is fired and the lifecycle service is re-invoked

#### Scenario: Tapping Resume writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on a paused budget and taps "Resume Budget"
- **THEN** `BudgetLifecycleService.resumeBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_resumed` analytics event is fired and the lifecycle service is re-invoked

#### Scenario: Menu exposes a VoiceOver label

- **WHEN** VoiceOver focuses the ellipsis Menu button
- **THEN** it announces the localized string for key `budgetDetail.menu.accessibilityLabel`

#### Scenario: Reset Carry-Over menu item exposes a VoiceOver hint

- **WHEN** VoiceOver focuses the Reset Carry-Over… menu item on a recurring budget with carry-over enabled
- **THEN** it announces the localized string for key `budgetDetail.menu.resetCarryOver.accessibilityHint`

#### Scenario: Reset Budget menu item exposes a VoiceOver hint

- **WHEN** VoiceOver focuses the Reset Budget… menu item
- **THEN** it announces the localized string for key `budgetDetail.menu.resetBudget.accessibilityHint`

### Requirement: Header announces composed VoiceOver label distinguishing on-budget vs over-budget

The header SHALL provide a single combined accessibility element (`accessibilityElement(children: .combine)`) with a localized label that describes the current-period state:

- When `remaining >= 0`, the label SHALL use key `budgetDetail.header.accessibilityLabel` and include the formatted remaining amount and an inline period descriptor.
- When `remaining < 0`, the label SHALL use key `budgetDetail.header.accessibilityLabel.overBudget` and include the **positive** overage amount (i.e. `|remaining|`) and an inline period descriptor.

The inline period descriptor SHALL be sourced from `Budget.periodInlineLabel`. For recurring periods this resolves via `BudgetPeriod.inlineLabel` to dedicated per-locale strings ("daily", "weekly", "biweekly", "monthly"). For `.specificDates` budgets it resolves to a dedicated string (key `period.specificDates.inline.budgetDetail`, English source: "in this window") so the announcement reads naturally (e.g. "$941.00 remaining in this window" rather than "$941.00 remaining this specific dates period").

#### Scenario: On-budget recurring header announces remaining

- **WHEN** VoiceOver focuses the header for a recurring-period budget and `remaining >= 0`
- **THEN** the announced label uses key `budgetDetail.header.accessibilityLabel` and includes the formatted positive remaining amount and the recurring inline period descriptor

#### Scenario: On-budget Specific Dates header announces remaining

- **WHEN** VoiceOver focuses the header for a `.specificDates` budget and `remaining >= 0`
- **THEN** the announced label includes the formatted positive remaining amount and the Specific Dates inline descriptor (e.g. "$941.00 remaining in this window")

#### Scenario: Over-budget header announces positive overage

- **WHEN** VoiceOver focuses the header and `remaining < 0`
- **THEN** the announced label uses key `budgetDetail.header.accessibilityLabel.overBudget` and includes the formatted **positive** overage amount and the inline period descriptor; the negative sign is not announced literally
