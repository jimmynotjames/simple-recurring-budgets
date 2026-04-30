## 1. BudgetDetailView+ExpenseSection.swift

- [x] 1.1 In `expenseRow(_:)`, change `allowsFullSwipe: false` to `allowsFullSwipe: true` on the trailing swipe action.
- [x] 1.2 Replace the swipe button's action body (which sets `expenseToDelete = expense` and `showDeleteConfirm = true`) with a direct call to `deleteExpense(expense)`.

## 2. BudgetDetailView.swift

- [x] 2.1 Remove `@State var expenseToDelete: ExpenseItem?` and `@State var showDeleteConfirm = false` from the view's state properties.
- [x] 2.2 Remove the `.confirmationDialog` block keyed on `$showDeleteConfirm` (the one with title `budgetDetail.deleteExpense.dialog.title`, confirm button, cancel button, and conditional message by expense name).

## 3. Localizable.xcstrings

- [x] 3.1 Remove the `budgetDetail.deleteExpense.dialog.title` entry.
- [x] 3.2 Remove the `budgetDetail.deleteExpense.dialog.confirm` entry.
- [x] 3.3 Remove the `budgetDetail.deleteExpense.dialog.message` entry.
- [x] 3.4 Remove the `budgetDetail.deleteExpense.dialog.message.unnamed` entry.

## 4. Tests

- [x] 4.1 In `BudgetDetailViewActionsTests.swift`, review the `DeleteExpenseAlgorithmTests` suite — these test the underlying `context.delete` + save algorithm and require no changes.
- [x] 4.2 Add a test `deleteExpense_swipeDeleteCallsDirectly` verifying that calling `deleteExpense(_:)` directly (without staging via `expenseToDelete`) removes the expense — ensures the direct-call path is covered.

## 5. Docs

- [x] 5.1 In `docs/product-features-planning.md`, update any acceptance criterion that references the swipe-delete confirmation dialog to reflect the new immediate-delete behaviour.

## 6. Verify

- [x] 6.1 Build and run the full test suite (`make test`) — all existing tests pass.
- [x] 6.2 Confirm in Xcode that the String Catalog has no remaining references to the four removed keys.
