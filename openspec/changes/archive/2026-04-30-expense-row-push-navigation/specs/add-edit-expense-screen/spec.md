## MODIFIED Requirements

### Requirement: Add/Edit/View Expense screen is a single sheet for both create and edit modes

The system SHALL present a single SwiftUI view, `AddEditExpenseView`, used for both creating a new `ExpenseItem` (Add mode) and editing an existing `ExpenseItem` (Edit/View mode). Per F-2.04, the screen does NOT distinguish between Edit and View — Edit mode IS the View mode and there is no read-only toggle.

`AddEditExpenseView` SHALL NOT wrap its own body in a `NavigationStack`. The navigation context (and therefore the navigation bar that hosts the Cancel and Save toolbar items) SHALL be provided by the caller:

- When presented as a **sheet** (`SheetRoute.addExpense(Budget)`), `RootView` SHALL wrap `AddEditExpenseView` in a `NavigationStack` at the sheet presentation site.
- When presented as a **push** (`AppRoute.expenseDetail(ExpenseItem)`), `RootView`'s existing outer `NavigationStack` provides the navigation context; no additional wrapper is needed.

This ensures that the view is not embedded inside a nested `NavigationStack`, which would produce a double navigation bar when pushed.

The `AddEditExpenseView` previews SHALL also wrap the view in a `NavigationStack` so that the toolbar items (Cancel, Save) render correctly.

The two access paths are:

- `SheetRoute.addExpense(Budget)` — Add mode.
- `AppRoute.expenseDetail(ExpenseItem)` — existing expense (F-2.04: same surface for view and in-place edit), reached via push navigation from `BudgetDetailView`.

`SheetRoute.expense(ExpenseItem)` is removed (see `app-navigation` delta). No `SheetRoute` case for an existing expense remains.

The sheet's navigation title SHALL read `"Add Expense"` (key `addEditExpense.title.add`) in Add mode and `"Expense"` (key `addEditExpense.title.existing`) in Edit/View mode. The title SHALL be displayed inline (`.navigationBarTitleDisplayMode(.inline)`).

The screen SHALL expose two toolbar items: a leading Cancel button (key `addEditExpense.action.cancel`) that dismisses without persisting any changes, and a trailing Save button (key `addEditExpense.action.save`). In the push context, Cancel calls `dismiss()`, which pops the view from the `NavigationStack`.

#### Scenario: Add mode is presented via SheetRoute.addExpense (sheet)

- **WHEN** a caller sets `Router.sheet = .addExpense(budget)` for some `Budget`
- **THEN** `RootView` SHALL present a `NavigationStack` containing `AddEditExpenseView` configured for Add mode, with the in-flight `Budget` available to the VM for attachment on Save

#### Scenario: Existing expense path is presented via AppRoute.expenseDetail (push)

- **WHEN** the user taps an expense row on `BudgetDetailView`, appending `AppRoute.expenseDetail(expense)` to `router.path`
- **THEN** `RootView`'s `navigationDestination` SHALL push `AddEditExpenseView` configured for Edit/View mode, seeded from that `ExpenseItem`, inside the existing outer `NavigationStack` — no nested `NavigationStack` is introduced

#### Scenario: No nested NavigationStack when pushed

- **WHEN** `AppRoute.expenseDetail(expense)` is resolved by `RootView`'s `navigationDestination`
- **THEN** the resulting screen SHALL have exactly one navigation bar (from the outer `NavigationStack`); a double navigation bar SHALL NOT appear

#### Scenario: Sheet exposes Cancel and Save toolbar items

- **WHEN** the screen is visible in either Add or Edit/View mode (sheet or push)
- **THEN** the navigation bar SHALL show a leading Cancel button and a trailing Save button; no other toolbar items SHALL be present on this screen

#### Scenario: Cancel from push context pops the view

- **WHEN** the screen is pushed via `AppRoute.expenseDetail` and the user taps Cancel
- **THEN** `dismiss()` pops the view from the `NavigationStack`, returning to `BudgetDetailView`; no changes are persisted
