## ADDED Requirements

### Requirement: Tapping an expense row pushes AddEditExpenseView in Edit mode

Each expense row rendered in `BudgetDetailView` SHALL be wrapped in a tappable affordance (a `Button` with `.buttonStyle(.plain)`) whose action appends `AppRoute.expenseDetail(expense)` to `router.path`. `RootView` SHALL resolve that route to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`, presenting the screen as a push within the `NavigationStack`.

The row's visual appearance SHALL be unchanged from the non-tappable state — `.buttonStyle(.plain)` ensures no system button highlighting is applied. Swipe actions (trailing swipe-to-delete) SHALL continue to function because SwiftUI's swipe gesture takes priority over the tap gesture on list rows, and the `.swipeActions` modifier is applied outside the `Button` wrapper.

In Edit mode, `AddEditExpenseView` provides a leading Cancel toolbar button and a trailing Save toolbar button; the Cancel button, via `dismiss()`, pops the pushed view from the `NavigationStack`. No changes to `AddEditExpenseView` itself are required.

#### Scenario: Tapping a current-period expense row pushes the edit view

- **WHEN** the user taps an expense row in the Current section of `BudgetDetailView`
- **THEN** `AppRoute.expenseDetail(expense)` is appended to `router.path` and `RootView` pushes `AddEditExpenseView` seeded with that `ExpenseItem`

#### Scenario: Tapping a past-period expense row pushes the edit view

- **WHEN** the user taps an expense row in the Past section of `BudgetDetailView`
- **THEN** `AppRoute.expenseDetail(expense)` is appended to `router.path` and `RootView` pushes `AddEditExpenseView` seeded with that `ExpenseItem`

#### Scenario: Swipe-to-delete still works on tappable rows

- **WHEN** the user trailing-swipes an expense row (which is now wrapped in a tap `Button`)
- **THEN** the swipe delete action is presented (not the tap navigation); the expense is not navigated to

#### Scenario: Expense row visual appearance is unchanged

- **WHEN** the expense list renders in `BudgetDetailView`
- **THEN** each expense row retains its existing layout (name, relative date, amount, add-funds tint) with no visible button highlight, chevron disclosure indicator, or other affordance added by the tap wrapper

#### Scenario: Cancel from pushed edit view returns to Budget Detail

- **WHEN** the user taps an expense row and then taps Cancel in `AddEditExpenseView`
- **THEN** `dismiss()` pops the pushed view and the user is returned to `BudgetDetailView` with no changes persisted

#### Scenario: Save from pushed edit view returns to Budget Detail with changes persisted

- **WHEN** the user taps an expense row, edits a field, and taps Save
- **THEN** the edit is persisted, `dismiss()` pops the pushed view, and the user is returned to `BudgetDetailView` where the expense row reflects the updated values

#### Scenario: VoiceOver treats each expense row as a button

- **WHEN** VoiceOver focuses an expense row
- **THEN** it announces the button trait (because the row is wrapped in a `Button`) in addition to the existing combined accessibility label (amount, name, date)
