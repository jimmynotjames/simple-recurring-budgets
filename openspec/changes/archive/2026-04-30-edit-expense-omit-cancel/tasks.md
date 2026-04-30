## 1. Implementation

- [x] 1.1 In `AddEditExpenseView.swift`, wrap the leading `ToolbarItem(placement: .cancellationAction)` block in `if !viewModel.isEditing { … }` so the Cancel button is only rendered in Add mode.

## 2. Tests

- [x] 2.1 In `AddEditExpenseViewActionsTests.swift` (or create it alongside `BudgetDetailViewActionsTests.swift`), add a test `addMode_isEditingIsFalse` that constructs `AddEditExpenseViewModel(adding: budget)` and asserts `viewModel.isEditing == false` (confirms Cancel renders in Add mode).
- [x] 2.2 Add a test `editMode_isEditingIsTrue` that constructs `AddEditExpenseViewModel(editing: expense)` and asserts `viewModel.isEditing == true` (confirms Cancel is suppressed in Edit mode).

## 3. Doc Update

- [x] 3.1 In `docs/product-features-planning.md`, update the F-2.04 acceptance criteria to note that Cancel is shown in Add mode only; Edit mode relies on the system back button as the discard path.

## 4. Build and Test

- [x] 4.1 Run `make test` (or `bash scripts/test.sh`) and confirm all tests pass with no regressions.
