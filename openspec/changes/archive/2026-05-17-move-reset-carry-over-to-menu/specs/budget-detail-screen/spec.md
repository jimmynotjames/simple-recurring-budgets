## MODIFIED Requirements

### Requirement: Status header presents remaining, period, RemainingBar, and conditional carry-over chip

The first List section SHALL be a status header showing:

- The current-period **remaining** amount, formatted with the budget's `currencyCode` and `AppSettings.currencyDisplay`, rendered in the system large-title font with `monospacedDigit()`. When remaining is negative, the amount SHALL be tinted with `Color.moneyDeficit`; when zero or positive, the primary text color.
- The period label sourced from `BudgetPeriod.listLabel` ("Daily" / "Weekly" / "Biweekly" / "Monthly") rendered in the system callout font with secondary foreground.
- A `RemainingBar` decorative bar bound to `clamp(remaining / allocation, 0, 1)`, hidden from VoiceOver and following the same on-budget vs over-budget rules as the Budgets row (accent fill when remaining ≥ 0; full deficit fill when remaining < 0; empty when allocation is 0).
- When `Budget.isCarryOverEnabled == true`, a row beneath the bar containing a `CarryOverChip` (passing `lifecycle?.carryOverAmount ?? budget.carryOverAmount`, `currencyCode`, and `AppSettings.currencyDisplay`). The header SHALL NOT render any trailing action control on this row — the manual carry-over reset trigger lives in the toolbar overflow Menu (see the separate "Toolbar overflow Menu" requirement below). When `isCarryOverEnabled == false`, this row SHALL be omitted entirely.

The header SHALL collapse the amount and period label into a single accessibility element with the composed VoiceOver label specified by the dedicated requirement below.

The header's amount + period container SHALL switch from `HStackLayout` (`.firstTextBaseline` aligned) to `VStackLayout` (`.leading` aligned) when `dynamicTypeSize >= .xxxLarge`. Row spacing, amount-stack spacing, chip top spacing, and row vertical padding SHALL scale via `@ScaledMetric` relative to the relevant text style.

The header section SHALL set `listRowBackground(Color("CellBackground"))` and hide the row separator.

#### Scenario: Positive remaining renders with primary color

- **WHEN** the lifecycle service returns `remaining >= 0` for the budget
- **THEN** the amount text uses the primary text color and the period label uses the secondary text color

#### Scenario: Negative remaining renders in deficit color

- **WHEN** the lifecycle service returns `remaining < 0` for the budget
- **THEN** the amount text uses `Color.moneyDeficit` and the `RemainingBar` fills 100% of its width in `Color.moneyDeficit`

#### Scenario: Carry-over chip omitted when toggle is off

- **WHEN** `Budget.isCarryOverEnabled == false`
- **THEN** the header SHALL NOT render the carry-over chip row, regardless of the underlying `carryOverAmount` value

#### Scenario: Carry-over row visible when toggle is on

- **WHEN** `Budget.isCarryOverEnabled == true`
- **THEN** the header renders a `CarryOverChip` on a row beneath the `RemainingBar`, with no trailing action button in the header; the manual carry-over reset is triggered exclusively from the toolbar overflow Menu

#### Scenario: Header carry-over row is unaffected by the live carry-over magnitude

- **WHEN** `Budget.isCarryOverEnabled == true` and the live `carryOverAmount` is zero, positive, or negative
- **THEN** the header carry-over row renders in all three cases; the row's visibility depends only on `isCarryOverEnabled`, not on the magnitude or sign of `carryOverAmount`

#### Scenario: Horizontal amount layout below xxxLarge

- **WHEN** `dynamicTypeSize` is `.large`, `.xLarge`, or `.xxLarge`
- **THEN** the amount and period label render side-by-side aligned to the first text baseline

#### Scenario: Vertical amount layout at xxxLarge and above

- **WHEN** `dynamicTypeSize` is `.xxxLarge` or any larger accessibility size
- **THEN** the amount renders above the period label in a vertical stack aligned to the leading edge

---

### Requirement: Toolbar overflow Menu hosts Edit Budget and Reset Budget actions

The screen SHALL place a single `topBarTrailing` toolbar item rendered as a `Menu` whose label is the SF Symbol `ellipsis.circle`. The Menu SHALL contain, in order:

1. **Edit Budget** (key `budgetDetail.menu.editBudget`, system image `pencil`) — activating it sets `router.sheet = .editBudget(budget)`. Visible in every lifecycle state.
2. **Pause Budget** / **Resume Budget** (state-driven; see below).
3. A `Divider`.
4. **Reset Carry-Over…** (key `budgetDetail.menu.resetCarryOver`, system image `arrow.counterclockwise.circle`, `role: .destructive`) — activating it triggers the Reset Carry-Over confirmation flow. Visible only when `Budget.isCarryOverEnabled == true`; omitted entirely otherwise. Visible in every lifecycle state in which the screen is rendered, regardless of the live carry-over balance's magnitude or sign.
5. **Reset Budget…** (key `budgetDetail.menu.resetBudget`, system image `arrow.counterclockwise`, `role: .destructive`) — activating it triggers the Reset Budget confirmation flow.

The Pause/Resume item SHALL be:

- **Hidden** when `BudgetPeriod(rawValue: budget.period) == .specificDates` (Specific Dates budgets are not pausable per `docs/product-features-planning.md` F-2.08).
- **Hidden** when `BudgetLifecycleResult.lifecycleState == .postEnd` (a terminal budget cannot be paused or resumed per F-7.07).
- Otherwise, **visible** with state-driven label and icon:
  - When `lifecycleState == .active` or `.preStart`: the item reads "Pause Budget" (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`). Activating it calls `BudgetLifecycleService.pauseBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fires the `budget_paused` analytics event and re-invokes `BudgetLifecycleService.result(for:)`. No confirmation dialog is presented (pause is reversible).
  - When `lifecycleState == .paused`: the item reads "Resume Budget" (key `budgetDetail.menu.resumeBudget`, system image `play.circle`). Activating it performs the same Resume action as the primary action button.

The Menu SHALL provide a localized accessibility label (key `budgetDetail.menu.accessibilityLabel`). The Reset Carry-Over… menu item SHALL provide a localized accessibility hint (key `budgetDetail.menu.resetCarryOver.accessibilityHint`) whose en-US value is "Clears the carry-over balance to zero. Expenses are not affected." per the cross-cutting accessibility requirement in `docs/main-prd.md` §6.8. The Reset Budget… menu item SHALL provide a localized accessibility hint (key `budgetDetail.menu.resetBudget.accessibilityHint`) whose en-US value is "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused."

#### Scenario: Edit Budget opens the edit sheet

- **WHEN** the user taps the ellipsis Menu and selects Edit Budget
- **THEN** `router.sheet` is set to `SheetRoute.editBudget(budget)` and the Add/Edit Budget sheet opens in Edit mode for this budget

#### Scenario: Reset Carry-Over opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Carry-Over…
- **THEN** the Reset Carry-Over confirmation alert is presented (specified below)

#### Scenario: Reset Budget opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Budget…
- **THEN** the Reset Budget confirmation dialog is presented (specified below)

#### Scenario: Reset Carry-Over menu item uses the circled reset icon

- **WHEN** the user opens the ellipsis Menu on a budget with `isCarryOverEnabled == true`, in any lifecycle state
- **THEN** the Reset Carry-Over… item renders with system image `arrow.counterclockwise.circle` and `role: .destructive` (red foreground), visually distinct from the Reset Budget… item

#### Scenario: Reset Budget menu item uses the reset icon, not trash

- **WHEN** the user opens the ellipsis Menu in any lifecycle state
- **THEN** the Reset Budget… item renders with system image `arrow.counterclockwise` and `role: .destructive` (red foreground)

#### Scenario: Reset Carry-Over menu item is shown when carry-over is enabled

- **WHEN** the user opens the Menu on a budget with `Budget.isCarryOverEnabled == true`
- **THEN** the Menu contains a "Reset Carry-Over…" item (key `budgetDetail.menu.resetCarryOver`, system image `arrow.counterclockwise.circle`, `role: .destructive`) positioned beneath the `Divider` and above the "Reset Budget…" item

#### Scenario: Reset Carry-Over menu item is omitted when carry-over is disabled

- **WHEN** the user opens the Menu on a budget with `Budget.isCarryOverEnabled == false`
- **THEN** the Menu does NOT contain a "Reset Carry-Over…" item; the Divider is still present and Reset Budget… is still the only destructive item below it

#### Scenario: Reset Carry-Over menu item is shown regardless of carry-over balance value

- **WHEN** the user opens the Menu on a budget with `isCarryOverEnabled == true` and the live `carryOverAmount` is zero
- **THEN** the Reset Carry-Over… item is still present and selectable; visibility is gated only by `isCarryOverEnabled`, not by the current balance

#### Scenario: Pause item is shown for active recurring budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .active` and `period != "specificDates"`
- **THEN** the Menu contains a "Pause Budget" item (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`)

#### Scenario: Resume item is shown for paused budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .paused`
- **THEN** the Menu contains a "Resume Budget" item (key `budgetDetail.menu.resumeBudget`, system image `play.circle`)

#### Scenario: Pause/Resume item is hidden for Specific Dates budgets

- **WHEN** the user opens the Menu on a `.specificDates` budget
- **THEN** the Menu contains Edit Budget, optionally Reset Carry-Over… (when `isCarryOverEnabled == true`), and Reset Budget…, but no Pause Budget or Resume Budget item

#### Scenario: Pause/Resume item is hidden once budget is past endDate

- **WHEN** the user opens the Menu on a budget whose `endDate` has passed (`lifecycleState == .postEnd`)
- **THEN** the Menu contains Edit Budget, optionally Reset Carry-Over… (when `isCarryOverEnabled == true`), and Reset Budget…, but no Pause Budget or Resume Budget item

#### Scenario: Tapping Pause writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on an active daily budget and taps "Pause Budget"
- **THEN** `BudgetLifecycleService.pauseBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_paused` analytics event is fired and the lifecycle service is re-invoked so the chip and primary slot re-render in the paused presentation

#### Scenario: Tapping Resume writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on a paused budget and taps "Resume Budget"
- **THEN** `BudgetLifecycleService.resumeBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_resumed` analytics event is fired and the lifecycle service is re-invoked so the chip and primary slot re-render in the active presentation

#### Scenario: Menu exposes a VoiceOver label

- **WHEN** VoiceOver focuses the ellipsis Menu button
- **THEN** it announces the localized string for key `budgetDetail.menu.accessibilityLabel`

#### Scenario: Reset Carry-Over menu item exposes a VoiceOver hint

- **WHEN** VoiceOver focuses the Reset Carry-Over… menu item
- **THEN** it announces the localized string for key `budgetDetail.menu.resetCarryOver.accessibilityHint` (en-US: "Clears the carry-over balance to zero. Expenses are not affected.")

#### Scenario: Reset Budget menu item exposes an updated VoiceOver hint

- **WHEN** VoiceOver focuses the Reset Budget… menu item
- **THEN** it announces the localized string for key `budgetDetail.menu.resetBudget.accessibilityHint` (en-US: "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused.")

---

### Requirement: Reset Carry-Over presents a confirmation alert and zeros only carry-over

The Menu's "Reset Carry-Over…" item SHALL present a SwiftUI `.alert` titled with key `budgetDetail.resetCarryOver.alert.title` (en-US: "Reset carry-over?") and bodied with key `budgetDetail.resetCarryOver.alert.message` (en-US: "The carry-over balance will be cleared and start fresh from zero."). The alert SHALL expose exactly one explicit button: a destructive confirm button (key `budgetDetail.resetCarryOver.alert.confirm`, en-US: "Reset to Zero"). The implementation SHALL NOT add a redundant `role: .cancel` button; the platform provides dismissal per current iOS behavior (e.g. tap-outside where applicable).

On confirm, the screen SHALL invoke `BudgetLifecycleService.resetCarryOver(budget, context: context)` and SHALL NOT directly mutate `Budget` fields. The service SHALL, in a single atomic write, set `Budget.lastResetDate = now`, set `Budget.lastModified = now`, and persist via exactly one `ModelContext.save()` call. The live carry-over walker (per `docs/main-prd.md` §6.7) treats all periods whose end is at or before `lastResetDate` as excluded, producing a carry-over of zero from that moment forward. No `ExpenseItem` rows SHALL be deleted; no `LifecycleEvent` SHALL be inserted. After the service call returns, the screen SHALL fire the `carryOverReset` analytics event and re-invoke `BudgetLifecycleService.result(for:)` so the header `CarryOverChip` updates.

The Reset Carry-Over Menu item SHALL provide a localized VoiceOver hint (key `budgetDetail.menu.resetCarryOver.accessibilityHint`) describing the action's non-cascading destructive consequence.

The Reset Carry-Over operation is distinct from the Reset Budget operation (which also deletes every `ExpenseItem` and may auto-resume a paused budget) and from the Delete Budget operation owned by the Add/Edit Budget sheet (which removes the Budget and cascades expenses).

#### Scenario: Confirming Reset Carry-Over zeros only carry-over

- **WHEN** the user activates the Reset Carry-Over… Menu item and confirms the alert
- **THEN** `BudgetLifecycleService.resetCarryOver(budget, context:context)` is called once, `Budget.lastResetDate` and `Budget.lastModified` become the current date, `ModelContext.save()` is called exactly once, and **no** `ExpenseItem` rows are deleted and **no** `LifecycleEvent` is inserted

#### Scenario: Carry-over reads as zero after a successful reset

- **WHEN** the Reset Carry-Over write completes and the screen re-invokes `BudgetLifecycleService.result(for:)` with the current date
- **THEN** the returned `carryOverAmount` is `0` (the live walker excludes all periods whose end is at or before the new `lastResetDate`), and the header `CarryOverChip` re-renders showing the zero value

#### Scenario: Dismissing the alert without confirming preserves carry-over

- **WHEN** the user activates the Reset Carry-Over… Menu item and dismisses the alert without activating the destructive confirm action
- **THEN** the budget's `lastResetDate` and `lastModified` SHALL NOT be modified, no analytics event is fired, and the header `CarryOverChip` value SHALL NOT change

#### Scenario: Reset Carry-Over fires `carryOverReset` analytics exactly once

- **WHEN** the user activates the Reset Carry-Over… Menu item and confirms the alert
- **THEN** the `carryOverReset` Mixpanel event is fired exactly once after the service returns, with properties `period`, `carry_over_enabled`, `currency_code`, `budget_name`, and `budget_allocation_amount` populated from the budget (matching the shape used by `budget_reset` per `docs/analytics-spec.md`)

#### Scenario: Reset Carry-Over does NOT delete expenses

- **WHEN** the user confirms the Reset Carry-Over alert on a budget with one or more `ExpenseItem` rows
- **THEN** every `ExpenseItem` whose `budget == budget` SHALL remain in the store after the operation; the operation SHALL NOT call `context.delete(_)` on any `ExpenseItem`

#### Scenario: Reset Carry-Over is unavailable when carry-over is disabled

- **WHEN** the user opens the ellipsis Menu on a budget with `Budget.isCarryOverEnabled == false`
- **THEN** there is no Reset Carry-Over… menu item to activate; the carry-over reset flow cannot be initiated from this surface
