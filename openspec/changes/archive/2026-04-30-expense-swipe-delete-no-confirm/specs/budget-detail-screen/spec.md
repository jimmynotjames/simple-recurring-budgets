## MODIFIED Requirements

### Requirement: Trailing swipe immediately deletes one expense without confirmation

Each expense row SHALL expose a trailing `swipeActions(edge: .trailing, allowsFullSwipe: true)` containing exactly one destructive `Button` whose label is a `Label` composed of the localized title `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and the SF Symbol `trash`. Activating the swipe button (partial swipe + tap, or full trailing swipe) SHALL immediately call `deleteExpense(_:)` on the tapped expense.

There is no confirmation dialog for swipe-initiated expense deletion. The `@State` properties `expenseToDelete` and `showDeleteConfirm` SHALL be removed from `BudgetDetailView`.

On invocation, within a single `withAnimation` block, the system SHALL `context.delete(expense)` and call `ModelContext.save()` exactly once, then re-invoke `BudgetLifecycleService.refreshAndSave(_:settings:context:)`. The Budget itself SHALL NOT be modified except by the lifecycle service's normal roll-and-persist behavior.

The four localization keys that existed solely for the removed confirmation dialog SHALL be deleted from `Localizable.xcstrings`:
- `budgetDetail.deleteExpense.dialog.title`
- `budgetDetail.deleteExpense.dialog.confirm`
- `budgetDetail.deleteExpense.dialog.message`
- `budgetDetail.deleteExpense.dialog.message.unnamed`

#### Scenario: Full trailing swipe immediately deletes the expense

- **WHEN** the user performs a full trailing swipe on an expense row
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Partial swipe button tap immediately deletes the expense

- **WHEN** the user partially swipes a row to reveal the red Delete button and taps it
- **THEN** the expense is immediately deleted from the store; no confirmation dialog is presented

#### Scenario: Deletion removes only the targeted expense

- **WHEN** swipe-delete is invoked on one expense row
- **THEN** that `ExpenseItem` is removed from the store, `ModelContext.save()` is called exactly once, no sibling `ExpenseItem`s are affected, and the lifecycle service is re-invoked so the header re-derives `remaining`

#### Scenario: Localized delete button label is unchanged

- **WHEN** the user trailing-swipes any expense row
- **THEN** the action button label reads the localized string under key `budgetDetail.deleteExpense.swipeAction` (en-US "Delete") and uses the `trash` SF Symbol

## REMOVED Requirements

### Requirement: Trailing swipe presents a delete confirmation that removes one expense

**Reason**: Confirmation dialog removed in favour of immediate delete with full-swipe enabled. iOS swipe-to-delete is a well-understood destructive gesture; the dialog added friction without meaningful safety value for individual expense entries.

**Migration**: The `.confirmationDialog` keyed on `showDeleteConfirm`, the `@State var expenseToDelete`, and the `@State var showDeleteConfirm` properties are removed from `BudgetDetailView`. The four dialog-only localization keys are removed from `Localizable.xcstrings`. The swipe action now calls `deleteExpense(_:)` directly.
