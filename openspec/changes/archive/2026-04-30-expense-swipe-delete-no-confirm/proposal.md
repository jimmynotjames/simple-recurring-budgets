## Why

The swipe-to-delete gesture on expense rows in `BudgetDetailView` currently shows a confirmation dialog and requires the user to explicitly enable full-swipe by using `allowsFullSwipe: false`. This adds unnecessary friction to a common, reversible-feeling action — swipe-delete in a list is already a well-understood iOS pattern with sufficient affordance (the trailing red action button). Removing the confirmation dialog and enabling full-swipe aligns with iOS HIG expectations and makes the interaction faster.

## What Changes

- `allowsFullSwipe` on the swipe-delete action in `BudgetDetailView+ExpenseSection.swift` changes from `false` to `true`, allowing a full trailing swipe to immediately delete.
- The swipe action handler directly invokes `deleteExpense(_:)` instead of staging `expenseToDelete` and toggling `showDeleteConfirm`.
- The delete-expense confirmation dialog (`.confirmationDialog` keyed on `showDeleteConfirm`) is removed from `BudgetDetailView`.
- The `@State var expenseToDelete` and `@State var showDeleteConfirm` properties are removed from `BudgetDetailView`.
- Four localization keys that existed solely to support the now-removed confirmation dialog are removed from `Localizable.xcstrings`:
  - `budgetDetail.deleteExpense.dialog.title`
  - `budgetDetail.deleteExpense.dialog.confirm`
  - `budgetDetail.deleteExpense.dialog.message`
  - `budgetDetail.deleteExpense.dialog.message.unnamed`
- Tests in `BudgetDetailViewActionsTests.swift` are updated to reflect the removal of the confirmation-dialog flow.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `budget-detail-screen`: The expense-row swipe-delete interaction no longer presents a confirmation dialog; a full trailing swipe now immediately deletes the expense.

## Impact

- **`BudgetDetailView.swift`** — remove two `@State` properties and the `.confirmationDialog` for delete-expense.
- **`BudgetDetailView+ExpenseSection.swift`** — `allowsFullSwipe: true`; action directly calls `deleteExpense(_:)`.
- **`Localizable.xcstrings`** — four keys removed.
- **`BudgetDetailViewActionsTests.swift`** — remove or rewrite any tests covering the confirmation dialog trigger; existing `DeleteExpenseAlgorithmTests` remain unchanged (they test the underlying delete algorithm, not the dialog).
- No data model, CloudKit, or navigation changes.

## Doc alignment

- **`docs/product-features-planning.md`**: Expense deletion via swipe (F-2.xx) — if any acceptance criterion references a confirmation dialog for swipe-delete, it will need updating. No other feature IDs are affected.
- **`docs/tech-design-doc.md`**: No architecture or schema changes.
- **`docs/main-prd.md`**: No global constraints affected.
