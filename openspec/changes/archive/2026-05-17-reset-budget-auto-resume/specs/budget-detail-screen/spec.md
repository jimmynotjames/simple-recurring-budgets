## MODIFIED Requirements

### Requirement: Toolbar overflow Menu hosts Edit Budget and Reset Budget actions

The screen SHALL place a single `topBarTrailing` toolbar item rendered as a `Menu` whose label is the SF Symbol `ellipsis.circle`. The Menu SHALL contain, in order:

1. **Edit Budget** (key `budgetDetail.menu.editBudget`, system image `pencil`) — activating it sets `router.sheet = .editBudget(budget)`. Visible in every lifecycle state.
2. **Pause Budget** / **Resume Budget** (state-driven; see below).
3. A `Divider`.
4. **Reset Budget…** (key `budgetDetail.menu.resetBudget`, system image `arrow.counterclockwise`, `role: .destructive`) — activating it triggers the Reset Budget confirmation flow.

The Pause/Resume item SHALL be:

- **Hidden** when `BudgetPeriod(rawValue: budget.period) == .specificDates` (Specific Dates budgets are not pausable per `docs/product-features-planning.md` F-2.08).
- **Hidden** when `BudgetLifecycleResult.lifecycleState == .postEnd` (a terminal budget cannot be paused or resumed per F-7.07).
- Otherwise, **visible** with state-driven label and icon:
  - When `lifecycleState == .active` or `.preStart`: the item reads "Pause Budget" (key `budgetDetail.menu.pauseBudget`, system image `pause.circle`). Activating it calls `BudgetLifecycleService.pauseBudget(budget, context:context, now: Date())`, then — when the call returns `true` — fires the `budget_paused` analytics event and re-invokes `BudgetLifecycleService.result(for:)`. No confirmation dialog is presented (pause is reversible).
  - When `lifecycleState == .paused`: the item reads "Resume Budget" (key `budgetDetail.menu.resumeBudget`, system image `play.circle`). Activating it performs the same Resume action as the primary action button.

The Menu SHALL provide a localized accessibility label (key `budgetDetail.menu.accessibilityLabel`). The Reset Budget… menu item SHALL provide a localized accessibility hint (key `budgetDetail.menu.resetBudget.accessibilityHint`) whose en-US value is "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused." per the cross-cutting accessibility requirement in `docs/main-prd.md` §6.8.

#### Scenario: Edit Budget opens the edit sheet

- **WHEN** the user taps the ellipsis Menu and selects Edit Budget
- **THEN** `router.sheet` is set to `SheetRoute.editBudget(budget)` and the Add/Edit Budget sheet opens in Edit mode for this budget

#### Scenario: Reset Budget opens the destructive confirmation

- **WHEN** the user taps the ellipsis Menu and selects Reset Budget…
- **THEN** the Reset Budget confirmation dialog is presented (specified below)

#### Scenario: Reset Budget menu item uses the reset icon, not trash

- **WHEN** the user opens the ellipsis Menu in any lifecycle state
- **THEN** the Reset Budget… item renders with system image `arrow.counterclockwise` and `role: .destructive` (red foreground)

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

- **WHEN** VoiceOver focuses the ellipsis Menu button
- **THEN** it announces the localized string for key `budgetDetail.menu.accessibilityLabel`

#### Scenario: Reset Budget menu item exposes an updated VoiceOver hint

- **WHEN** VoiceOver focuses the Reset Budget… menu item
- **THEN** it announces the localized string for key `budgetDetail.menu.resetBudget.accessibilityHint` (en-US: "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused.")

---

### Requirement: Reset Budget presents a confirmation dialog and atomically wipes expenses, resets carry-over, and resumes if paused

The Menu's "Reset Budget…" item SHALL present a SwiftUI `confirmationDialog` titled with key `budgetDetail.resetBudget.dialog.title` and bodied with key `budgetDetail.resetBudget.dialog.message`. The dialog SHALL expose exactly one explicit button: a destructive confirm button (key `budgetDetail.resetBudget.dialog.confirm`). The implementation SHALL NOT add a redundant `role: .cancel` button; SwiftUI's implicit dismiss (e.g. tap-outside on iOS when presented as an anchored popover) SHALL provide the cancel path, consistent with the Add/Edit Budget and Add/Edit Expense delete confirmations.

The dialog body SHALL be a single static localized string under key `budgetDetail.resetBudget.dialog.message` (en-US: "All expenses will be permanently deleted, carry-over will reset to zero, and if paused, the budget will resume.") with no runtime arguments and no expense count in the copy.

On confirm, the screen SHALL wrap the call in a `withAnimation` block and invoke `BudgetLifecycleService.resetBudget(budget, context: context, now: Date())`. The screen SHALL NOT directly mutate `Budget` fields or `ExpenseItem` rows for this action; all write logic lives in the service.

`BudgetLifecycleService.resetBudget(_:context:now:)` SHALL, in a single atomic write:

1. Iterate `Array(budget.expenseItems)` and call `context.delete(_)` on each `ExpenseItem`.
2. Set `Budget.lastResetDate = now` so the live carry-over walker excludes all prior periods (per `docs/main-prd.md` §6.7 — there is no stored `carryOverAmount` field to zero; carry-over is recomputed live).
3. Set `Budget.lastModified = now`.
4. Compute the current lifecycle state via `BudgetCalculator.snapshot(...)`. If `lifecycleState == .paused`, insert a new `LifecycleEvent(budget: budget, kind: .resume, effectiveDate: now)` into the same `ModelContext`. The implementation SHALL NOT call `BudgetLifecycleService.resumeBudget(...)` here — that method saves internally, which would break the single-save atomicity guarantee. The inline event insertion is safe because reaching the `.paused` branch guarantees the budget is recurring (Specific Dates budgets cannot be paused per F-2.08) and not `.postEnd` (a `.postEnd` budget cannot have lifecycle state `.paused`).
5. Persist via exactly one `ModelContext.save()` call covering all of the above.

After the service call returns, the screen SHALL fire the `budget_reset` analytics event (unchanged: a single event regardless of whether the auto-resume branch was taken) and re-invoke `BudgetLifecycleService.result(for:)` so the header and lists re-render. The Budget itself SHALL NOT be deleted.

The Reset Budget operation is distinct from the Reset Carry-Over operation (which only sets `lastResetDate`) and from the Delete Budget operation owned by the Add/Edit Budget sheet (which removes the Budget and cascades expenses). The capability `budget-detail-screen` SHALL NOT introduce a Delete Budget entry point on this screen.

#### Scenario: Reset Budget dialog body is static and localized

- **WHEN** the user opens the Reset Budget dialog (any number of expenses, including zero; paused or not)
- **THEN** the dialog body is rendered from key `budgetDetail.resetBudget.dialog.message` as a single String Catalog entry (en-US: "All expenses will be permanently deleted, carry-over will reset to zero, and if paused, the budget will resume.") with no count interpolation and no runtime arguments

#### Scenario: Confirming Reset Budget on an active budget deletes expenses and updates lastResetDate in one save

- **WHEN** the user activates Reset Budget… from the Menu on a budget whose `lifecycleState != .paused` and confirms the dialog
- **THEN** every `ExpenseItem` whose `budget == budget` is removed from the store, `Budget.lastResetDate` and `Budget.lastModified` become `now`, **no** `LifecycleEvent` of any kind is inserted, and `ModelContext.save()` is called exactly once for the entire operation

#### Scenario: Confirming Reset Budget on a paused budget also resumes it in one save

- **WHEN** the user activates Reset Budget… from the Menu on a budget whose `lifecycleState == .paused` and confirms the dialog
- **THEN** every `ExpenseItem` whose `budget == budget` is removed from the store, `Budget.lastResetDate` and `Budget.lastModified` become `now`, exactly one new `LifecycleEvent(budget: budget, kind: .resume, effectiveDate: now)` is inserted into the same context, `ModelContext.save()` is called exactly once covering all mutations, and after the post-save re-invoke of `BudgetLifecycleService.result(for:)` the budget's `lifecycleState` resolves to `.active`

#### Scenario: Auto-resume reuses the same `now` timestamp

- **WHEN** the service path inserts an auto-resume `LifecycleEvent` during a Reset Budget call invoked with `now = N`
- **THEN** the inserted event's `effectiveDate == N` and `Budget.lastResetDate == N` and `Budget.lastModified == N` (one shared timestamp across all writes)

#### Scenario: Reset Budget fires `budget_reset` analytics exactly once regardless of paused state

- **WHEN** the user activates Reset Budget… on a budget in any lifecycle state and confirms the dialog
- **THEN** the `budget_reset` Mixpanel event is fired exactly once after the service returns; no `budget_resumed` event is fired for the auto-resume branch (the auto-resume is system-initiated, not a user-initiated action)

#### Scenario: Reset Budget does NOT delete the Budget entity

- **WHEN** the user confirms the Reset Budget dialog
- **THEN** the `Budget` entity SHALL remain in the store (no `context.delete(budget)` call), the screen stays on the same `BudgetDetailView`, and the navigation stack does not pop

#### Scenario: Dismissing the Reset Budget dialog without confirming preserves the budget's data

- **WHEN** the user activates Reset Budget… and dismisses the confirmation dialog without activating the destructive confirm action
- **THEN** no `ExpenseItem` is deleted, no `LifecycleEvent` is inserted, and the budget's `lastResetDate` and `lastModified` are unchanged
