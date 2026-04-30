## Why

Expense rows in `BudgetDetailView` are display-only: tapping them does nothing. The infrastructure for editing an existing expense (`SheetRoute.expense`, `AddEditExpenseView` in edit mode) was built under F-2.04 (`add-edit-expense-screen`) but the `BudgetDetailView` entry point was explicitly deferred. That deferral was never revisited after F-2.04 shipped. The missing tap-to-edit behaviour is now the only remaining gap between the implemented budget-detail screen and a fully functional expense management flow. Per the user's direction, the transition from the expense row to the edit screen should be a **push** (NavigationStack push, standard iOS back-button return) rather than a sheet presentation—which is the natural iOS pattern for a drill-in detail from a list that is itself already pushed onto the stack.

## What Changes

- **New `AppRoute.expenseDetail(ExpenseItem)` case** — extends the `AppRoute` enum so that expense-row taps can be expressed as a type-safe push destination.
- **`BudgetDetailView` expense rows become tappable** — wrapping each row in a `Button` (or equivalent) that appends `.expenseDetail(expense)` to `router.path`.
- **`RootView.navigationDestination` wiring** — resolves `AppRoute.expenseDetail(expense)` to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`.
- **`SheetRoute.expense(ExpenseItem)` disposition** — the case was introduced by `add-edit-expense-screen` for a sheet-based edit path, but now has no entry point. This change removes it from `SheetRoute` (and from `RootView`'s sheet switch) to avoid dead code. **BREAKING** (within the app's own navigation layer; no external API surface).
- **Spec and doc updates** — `openspec/specs/budget-detail-screen/spec.md` gains the tap requirement; `openspec/specs/app-navigation/spec.md` gains the new `AppRoute` case and removes the now-deleted `SheetRoute.expense` case; `docs/product-features-planning.md` F-2.02 note is updated to reflect the entry point is now implemented.
- **Tests** — unit tests for the new routing behaviour added to the existing `BudgetDetailViewActionsTests` suite.

## Capabilities

### New Capabilities

_(none — no net-new capability specs; all behaviour is an extension of existing capabilities)_

### Modified Capabilities

- `app-navigation`: adds `AppRoute.expenseDetail(ExpenseItem)` push case; removes `SheetRoute.expense(ExpenseItem)` which is now without an entry point.
- `budget-detail-screen`: adds the requirement and scenarios for tapping an expense row to push `AppRoute.expenseDetail(expense)` onto the navigation stack.

## Impact

- **`simple-recurring-budgets/Navigation/Router.swift`** (or wherever `AppRoute`/`SheetRoute` are defined) — new `AppRoute.expenseDetail(ExpenseItem)` case; `SheetRoute.expense(ExpenseItem)` removed.
- **`simple-recurring-budgets/Views/RootView.swift`** — new `navigationDestination` branch for `.expenseDetail`; `SheetRoute.expense` branch removed from sheet switch.
- **`simple-recurring-budgets/Views/BudgetDetailView+ExpenseSection.swift`** — `expenseRow(_:)` gains a tap `Button` action.
- **`simple-recurring-budgetsTests/Views/BudgetDetailViewActionsTests.swift`** — new tests for tap routing.
- **`docs/product-features-planning.md`** — F-2.02 edge-case note updated.
- **`openspec/specs/app-navigation/spec.md`** — delta applied.
- **`openspec/specs/budget-detail-screen/spec.md`** — delta applied.

## Conflicts with docs

**`openspec/specs/add-edit-expense-screen/spec.md`** states the screen is presented "from the existing `Router.sheet` mechanism via two existing `SheetRoute` cases" and lists `SheetRoute.expense(ExpenseItem)` as the edit-mode route. This change removes that case and instead reaches `AddEditExpenseView` via a push `AppRoute`. The spec requirement about presentation mechanism is intentionally overridden; the spec will need a minor update noting push as the navigation mode for the existing-expense path from `BudgetDetailView`. Resolution: update the spec in the delta to reflect the push path; the view itself is unchanged.
