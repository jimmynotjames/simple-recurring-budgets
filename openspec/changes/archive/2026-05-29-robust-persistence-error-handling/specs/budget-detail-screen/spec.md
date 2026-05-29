## MODIFIED Requirements

### Requirement: Trailing swipe immediately deletes one expense without confirmation

Each expense row SHALL expose a trailing `swipeActions(edge: .trailing, allowsFullSwipe: true)` containing exactly one destructive `Button` whose label is a `Label` composed of the localized title `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and the SF Symbol `trash`. Activating the swipe button (partial swipe + tap, or full trailing swipe) SHALL immediately call `deleteExpense(_:)` on the tapped expense.

There is no confirmation dialog for swipe-initiated expense deletion. The `@State` properties `expenseToDelete` and `showDeleteConfirm` SHALL NOT exist on `BudgetDetailView`.

On invocation, within a single `withAnimation` block, the system SHALL `context.delete(expense)` and persist the deletion via the shared persistence-save helper (operation `expense_delete`) exactly once, then re-invoke `BudgetLifecycleService.result(for:)` on success. The Budget itself SHALL NOT be modified except by the lifecycle service's normal roll-and-persist behavior.

If the persistence-save helper throws, the deletion is surfaced as an *interactive* save failure: the system SHALL present the standard save-error alert (see the `persistence-error-handling` capability) over the Budget detail screen, the `expense_deleted` analytics event SHALL NOT fire, and Retry SHALL re-attempt the same delete-and-save. The four localization keys that existed solely for the removed confirmation dialog SHALL NOT be present in `Localizable.xcstrings`:
- `budgetDetail.deleteExpense.dialog.title`
- `budgetDetail.deleteExpense.dialog.confirm`
- `budgetDetail.deleteExpense.dialog.message`
- `budgetDetail.deleteExpense.dialog.message.unnamed`

#### Scenario: Full trailing swipe immediately deletes the expense

- **WHEN** the user performs a full trailing swipe on an expense row and the save succeeds
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Partial swipe button tap immediately deletes the expense

- **WHEN** the user partially swipes a row to reveal the red Delete button and taps it, and the save succeeds
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Deletion removes only the targeted expense

- **WHEN** swipe-delete is invoked on one expense row and the save succeeds
- **THEN** that `ExpenseItem` is removed from the store, the save helper is called exactly once, no sibling `ExpenseItem`s are affected, and the lifecycle service is re-invoked so the header re-derives `remaining`

#### Scenario: Localized delete button label is unchanged

- **WHEN** the user trailing-swipes any expense row
- **THEN** the action button label reads the localized string under key `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and uses the `trash` SF Symbol

#### Scenario: Failed swipe-delete surfaces the save-error alert

- **WHEN** swipe-delete is invoked and the persistence-save helper throws
- **THEN** the save-error alert is presented over the Budget detail screen, no `expense_deleted` analytics event is fired, and Retry re-attempts the same delete-and-save
