## MODIFIED Requirements

### Requirement: Primary action section presents a full-width Add Expense button

The second List section SHALL be a single full-width primary action button styled `.borderedProminent` at `.controlSize(.large)` with the system headline font. The button's label, action, and the caption beneath it SHALL be state-driven from `BudgetLifecycleResult.lifecycleState`:

- **`.active`, `.preStart`, `.postEnd`** — the button SHALL be a `Label` composed of the localized title (key `budgetDetail.action.addExpense`, en-US "Add Expense") and the SF Symbol `plus`. Activating it SHALL set `router.sheet = .addExpense(budget)` for this specific budget. No caption is rendered beneath the button. The button SHALL provide a localized accessibility label that includes the budget's name (key `budgetDetail.action.addExpense.accessibilityLabel`) and a localized accessibility hint (key `budgetDetail.action.addExpense.accessibilityHint`).
- **`.paused`** — the button SHALL be a `Label` composed of the localized title (key `budgetDetail.action.resume`, en-US "Resume Budget") and the SF Symbol `play.circle`. Activating it SHALL call `BudgetLifecycleService.resumeBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fire the `budget_resumed` analytics event (see budget-detail-screen analytics requirements) and re-invoke `BudgetLifecycleService.result(for:)`. Directly below the button, in `.caption`/`.secondary` styling, a single line SHALL render the localized caption `budgetDetail.action.resume.caption.format` (en-US "Paused since %@. Resume to log expenses.") with the formatted `BudgetLifecycleResult.pausedSince` (locale-aware `Date.formatted(date: .abbreviated, time: .omitted)`). The caption is the only paused-state explainer on this surface; there is no separate disabled Add Expense affordance. The button SHALL provide a localized accessibility label (key `budgetDetail.action.resume.accessibilityLabel`) and accessibility hint (key `budgetDetail.action.resume.accessibilityHint`).

The section SHALL use `listRowBackground(Color.clear)`, hide the row separator, and apply `listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))` so the button reads as a free-standing prominent action rather than a List row.

#### Scenario: Active state shows Add Expense

- **WHEN** the lifecycle service returns `lifecycleState == .active`
- **THEN** the primary button reads "Add Expense" with the SF Symbol `plus`, no caption is rendered below it, and activating it sets `router.sheet = SheetRoute.addExpense(budget)`

#### Scenario: Pre-start state still shows Add Expense

- **WHEN** the lifecycle service returns `lifecycleState == .preStart`
- **THEN** the primary button continues to read "Add Expense" and remains active (future-dated entries within the window are legitimate per F-2.04)

#### Scenario: Post-end state still shows Add Expense

- **WHEN** the lifecycle service returns `lifecycleState == .postEnd`
- **THEN** the primary button continues to read "Add Expense" and remains active (late-logged entries within the window are legitimate per F-2.04)

#### Scenario: Paused state replaces Add Expense with Resume Budget

- **WHEN** the lifecycle service returns `lifecycleState == .paused` and `pausedSince = 2026-05-01`
- **THEN** the primary button reads "Resume Budget" with the SF Symbol `play.circle`, a single caption "Paused since May 1, 2026. Resume to log expenses." renders in `.caption`/`.secondary` styling directly below the button, and activating the button invokes `BudgetLifecycleService.resumeBudget(...)`

#### Scenario: Successful Resume swaps the button back to Add Expense

- **WHEN** the user activates the Resume Budget button and `BudgetLifecycleService.resumeBudget(...)` returns `true`
- **THEN** the lifecycle service is re-invoked, `BudgetLifecycleResult.lifecycleState` becomes `.active`, and the primary button re-renders as "Add Expense"

#### Scenario: Add Expense VoiceOver label includes the budget name

- **WHEN** VoiceOver focuses the primary action button in the `.active` state
- **THEN** the announced label uses key `budgetDetail.action.addExpense.accessibilityLabel` and includes the budget's name; the announced hint uses key `budgetDetail.action.addExpense.accessibilityHint`

#### Scenario: Resume Budget VoiceOver label

- **WHEN** VoiceOver focuses the primary action button in the `.paused` state
- **THEN** the announced label uses key `budgetDetail.action.resume.accessibilityLabel` and the announced hint uses key `budgetDetail.action.resume.accessibilityHint`

### Requirement: Toolbar overflow Menu hosts Edit Budget and Reset Budget actions

The screen SHALL place a single `topBarTrailing` toolbar item rendered as a `Menu` whose label is the SF Symbol `ellipsis.circle`. The Menu SHALL contain, in order:

1. **Edit Budget** (key `budgetDetail.menu.editBudget`, system image `pencil`) — activating it sets `router.sheet = .editBudget(budget)`. Visible in every lifecycle state.
2. **Pause Budget** / **Resume Budget** (state-driven; see below).
3. A `Divider`.
4. **Reset Budget…** (key `budgetDetail.menu.resetBudget`, system image `trash`, `role: .destructive`) — activating it triggers the Reset Budget confirmation flow.

The Pause/Resume item SHALL be:

- **Hidden** when `BudgetPeriod(rawValue: budget.period) == .specificDates` (Specific Dates budgets are not pausable per `docs/product-features-planning.md` F-2.08).
- **Hidden** when `BudgetLifecycleResult.lifecycleState == .postEnd` (a terminal budget cannot be paused or resumed per F-7.07).
- Otherwise, **visible** with state-driven label and icon:
  - When `lifecycleState == .active` or `.preStart`: the item reads "Pause Budget" (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`). Activating it calls `BudgetLifecycleService.pauseBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fires the `budget_paused` analytics event and re-invokes `BudgetLifecycleService.result(for:)`. No confirmation dialog is presented (pause is reversible).
  - When `lifecycleState == .paused`: the item reads "Resume Budget" (key `budgetDetail.menu.resumeBudget`, system image `play.circle`). Activating it performs the same Resume action as the primary action button.

The Menu SHALL provide a localized accessibility label (key `budgetDetail.menu.accessibilityLabel`).

#### Scenario: Edit Budget opens the edit sheet

- **WHEN** the user taps the ellipsis Menu and selects Edit Budget
- **THEN** `router.sheet` is set to `SheetRoute.editBudget(budget)` and the Add/Edit Budget sheet opens in Edit mode for this budget

#### Scenario: Reset Budget opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Budget…
- **THEN** the Reset Budget confirmation dialog is presented

#### Scenario: Pause item is shown for active recurring budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .active` and `period != "specificDates"`
- **THEN** the Menu contains a "Pause Budget" item (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`)

#### Scenario: Resume item is shown for paused budgets

- **WHEN** the user opens the Menu on a daily budget with `lifecycleState == .paused`
- **THEN** the Menu contains a "Resume Budget" item (key `budgetDetail.menu.resumeBudget`, system image `play.circle`)

#### Scenario: Pause/Resume item is hidden for Specific Dates budgets

- **WHEN** the user opens the Menu on a `.specificDates` budget
- **THEN** the Menu contains Edit Budget and Reset Budget…, but no Pause Budget or Resume Budget item

#### Scenario: Pause/Resume item is hidden once budget is past endDate

- **WHEN** the user opens the Menu on a budget whose `endDate` has passed (`lifecycleState == .postEnd`)
- **THEN** the Menu contains Edit Budget and Reset Budget…, but no Pause Budget or Resume Budget item

#### Scenario: Tapping Pause writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on an active daily budget and taps "Pause Budget"
- **THEN** `BudgetLifecycleService.pauseBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_paused` analytics event is fired and the lifecycle service is re-invoked so the chip and primary slot re-render in the paused presentation

#### Scenario: Tapping Resume writes a LifecycleEvent and fires analytics

- **WHEN** the user opens the Menu on a paused budget and taps "Resume Budget"
- **THEN** `BudgetLifecycleService.resumeBudget(budget, context:context, now:)` is called once, no confirmation dialog is presented, and on a `true` return the `budget_resumed` analytics event is fired and the lifecycle service is re-invoked so the chip and primary slot re-render in the active presentation

#### Scenario: Menu exposes a VoiceOver label

- **WHEN** VoiceOver focuses the toolbar Menu
- **THEN** the announced label uses key `budgetDetail.menu.accessibilityLabel`

## ADDED Requirements

### Requirement: Status header renders paused presentation when lifecycle state is paused

When `BudgetLifecycleResult.lifecycleState == .paused`, the status header SHALL render its values with a paused visual treatment:

- The large remaining amount SHALL use `.foregroundStyle(.secondary)` (the greyed value treatment) regardless of sign, overriding the default primary-text / `Color.moneyDeficit` rules for non-paused states.
- Below the period label, the header SHALL render a single line of `.caption`/`.secondary` text with the localized caption `chip.paused.caption.format` (en-US "Paused since %@") using `BudgetLifecycleResult.pausedSince` formatted via `Date.formatted(date: .abbreviated, time: .omitted)`.
- When `Budget.isCarryOverEnabled == true`, the `CarryOverChip` SHALL continue to render but with `.foregroundStyle(.secondary)` overriding its surplus/deficit color treatment. The chip's value SHALL remain live — backdated edits to prior active periods MAY still change it.
- The header's composed VoiceOver label SHALL use a paused-state key (`budgetDetail.header.accessibilityLabel.paused`) that includes the formatted remaining amount, the inline period name, and the formatted `pausedSince` date.

When `BudgetLifecycleResult.lifecycleState != .paused`, none of the paused-state treatments above SHALL apply; the header renders per the original active / negative / pre-start / post-end rules.

#### Scenario: Paused header renders greyed value with "Paused since" caption

- **WHEN** the lifecycle service returns `lifecycleState == .paused`, `remaining = 7.50`, and `pausedSince = 2026-05-01`
- **THEN** the large remaining amount renders with `.foregroundStyle(.secondary)`, and a `.caption`/`.secondary` line below the period label reads "Paused since May 1, 2026"

#### Scenario: Paused carry-over chip stays visible but greyed

- **WHEN** `lifecycleState == .paused` and `Budget.isCarryOverEnabled == true`
- **THEN** the `CarryOverChip` continues to render in the header with its formatted carry-over amount, but its foreground style is overridden to `.secondary` and its background tint is unchanged from active-state styling

#### Scenario: Paused chip value updates on backdated edits

- **WHEN** the budget is paused and the user edits an `ExpenseItem` whose `date` falls inside a prior active period
- **THEN** the next `BudgetLifecycleService.result(for:)` call returns the recomputed `carryOverAmount` and the header chip re-renders with the new value (still in the paused presentation)

#### Scenario: Paused header VoiceOver label

- **WHEN** VoiceOver focuses the header in the `.paused` state
- **THEN** the announced label uses key `budgetDetail.header.accessibilityLabel.paused` and includes the formatted remaining amount, the inline period name, and the formatted `pausedSince` date

### Requirement: Pause and resume analytics events

The screen SHALL fire dedicated Mixpanel events on successful Pause and Resume actions, following the sibling-pattern boundary established by F-8.01 and F-8.02 (`OSLog` and `AnalyticsClient` are independent siblings; neither is derived from the other).

The events SHALL be:

- `budget_paused` (constant `AnalyticsEvent.budgetPaused`) — fired immediately after `BudgetLifecycleService.pauseBudget(...)` returns `true`. Properties: `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount` (same shape as `budget_reset`, per `docs/analytics-spec.md` event taxonomy).
- `budget_resumed` (constant `AnalyticsEvent.budgetResumed`) — fired immediately after `BudgetLifecycleService.resumeBudget(...)` returns `true`. Same property shape as `budget_paused`.

The screen SHALL NOT fire either event when the underlying service call returns `false`. The screen SHALL log a corresponding `Logger.ui.debug` line for each action (matching the existing pattern in `resetCarryOver` and `resetBudget`) as a sibling of the analytics call; neither call is derived from the other.

No personally-identifying information SHALL be included in event properties beyond the accepted-risk allow-list (`budget_name`, `budget_allocation_amount`) already defined in `docs/analytics-spec.md` §5.4.

#### Scenario: Pause emits budget_paused on success

- **WHEN** the user taps Pause Budget and `BudgetLifecycleService.pauseBudget(...)` returns `true`
- **THEN** `analytics.track(AnalyticsEvent.budgetPaused, properties: [...])` is called exactly once with `period`, `carry_over_enabled`, `currency_code`, `budget_name`, `budget_allocation_amount` populated from the budget

#### Scenario: Resume emits budget_resumed on success

- **WHEN** the user taps Resume Budget (from either the toolbar item or the primary action button) and `BudgetLifecycleService.resumeBudget(...)` returns `true`
- **THEN** `analytics.track(AnalyticsEvent.budgetResumed, properties: [...])` is called exactly once with the same property shape

#### Scenario: No event is fired when the service rejects the action

- **WHEN** the user taps Pause Budget on a budget whose `lifecycleState` is already `.paused` (defensive — UI shouldn't expose the action in this state) and `pauseBudget(...)` returns `false`
- **THEN** no `budget_paused` event is fired; the analytics call site is gated on the service's return value
