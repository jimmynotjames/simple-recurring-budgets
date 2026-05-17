## MODIFIED Requirements

### Requirement: Primary action section presents a full-width Add Expense button

The second List section SHALL be a single full-width primary action button styled `.borderedProminent` at `.controlSize(.large)` with the system headline font. The button's label, action, and the caption beneath it SHALL be state-driven from `BudgetLifecycleResult.lifecycleState`:

- **`.active`, `.preStart`, `.postEnd`** — the button SHALL be a `Label` composed of the localized title (key `budgetDetail.action.addExpense`, en-US "Add Expense") and the SF Symbol `plus`. Activating it SHALL set `router.sheet = .addExpense(budget)` for this specific budget. No caption is rendered beneath the button. The button SHALL provide a localized accessibility label that includes the budget's name (key `budgetDetail.action.addExpense.accessibilityLabel`) and a localized accessibility hint (key `budgetDetail.action.addExpense.accessibilityHint`).
- **`.paused`** — the button SHALL be a `Label` composed of the localized title (key `budgetDetail.action.resume`, en-US "Resume Budget") and the SF Symbol `play.circle`. Activating it SHALL call `BudgetLifecycleService.resumeBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fire the `budget_resumed` analytics event (see budget-detail-screen analytics requirements) and re-invoke `BudgetLifecycleService.result(for:)`. Directly below the button, in `.caption`/`.secondary` styling, a single line SHALL render the localized caption `budgetDetail.action.resume.caption.format` (en-US "Paused since %@. Resume to log new expenses.") with the formatted `BudgetLifecycleResult.pausedSince` (locale-aware `Date.formatted(date: .abbreviated, time: .omitted)`). The caption is the only paused-state explainer on this surface; there is no separate disabled Add Expense affordance. The button SHALL provide a localized accessibility label (key `budgetDetail.action.resume.accessibilityLabel`) and accessibility hint (key `budgetDetail.action.resume.accessibilityHint`).

The section SHALL use `listRowBackground(Color.clear)`, hide the row separator, and apply `listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))` so the button reads as a free-standing prominent action rather than a List row.

The "Resume to log **new** expenses" wording quietly acknowledges that backdated entries via the Budgets-list `+` button remain available while paused (per the `add-edit-expense-screen` date-bounds requirement). The Detail screen itself does not surface a backdated-entry affordance — the list `+` is the entry point for that path — but the caption avoids over-claiming that all expense entry is blocked.

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
- **THEN** the primary button reads "Resume Budget" with the SF Symbol `play.circle`, a single caption "Paused since May 1, 2026. Resume to log new expenses." renders in `.caption`/`.secondary` styling directly below the button, and activating the button invokes `BudgetLifecycleService.resumeBudget(...)`

#### Scenario: Successful Resume swaps the button back to Add Expense

- **WHEN** the user activates the Resume Budget button and `BudgetLifecycleService.resumeBudget(...)` returns `true`
- **THEN** the lifecycle service is re-invoked, `BudgetLifecycleResult.lifecycleState` becomes `.active`, and the primary button re-renders as "Add Expense"

#### Scenario: Add Expense VoiceOver label includes the budget name

- **WHEN** VoiceOver focuses the primary action button in the `.active` state
- **THEN** the announced label uses key `budgetDetail.action.addExpense.accessibilityLabel` and includes the budget's name; the announced hint uses key `budgetDetail.action.addExpense.accessibilityHint`

#### Scenario: Resume Budget VoiceOver label

- **WHEN** VoiceOver focuses the primary action button in the `.paused` state
- **THEN** the announced label uses key `budgetDetail.action.resume.accessibilityLabel` and the announced hint uses key `budgetDetail.action.resume.accessibilityHint`
