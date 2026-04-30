## Context

`BudgetDetailView` is already a pushed screen (reached via `AppRoute.budgetDetail(Budget)` → `NavigationStack`). Its expense rows are display-only; tapping does nothing. The `AddEditExpenseView` form exists and works for both Add and Edit modes, and is already presented as a sheet for the Add Expense flow (`router.sheet = .addExpense(budget)`). `SheetRoute.expense(ExpenseItem)` was introduced in the `add-edit-expense-screen` change but has no entry point today — it is dead code wired in `RootView`.

The decision to use **push** for the expense-row tap (rather than a sheet) was explicit product direction. On a screen that is itself pushed, drilling into an item via push gives a natural back-button return and keeps the navigation stack semantically flat (list → detail → item). A sheet on top of a pushed view is a valid iOS pattern but creates a visual modal "interruption" that is less natural for an inline drill-in.

## Goals / Non-Goals

**Goals:**
- Expense rows in `BudgetDetailView` become tappable and push `AddEditExpenseView` in Edit mode.
- A new `AppRoute.expenseDetail(ExpenseItem)` case cleanly expresses this destination.
- `SheetRoute.expense(ExpenseItem)` is removed — it had no entry point and its purpose is now fulfilled by the push path.
- `RootView` gains a `navigationDestination` branch for `.expenseDetail` and loses the sheet branch for `.expense`.
- Specs (`app-navigation`, `budget-detail-screen`) and `docs/product-features-planning.md` are updated to reflect the implemented behaviour.
- Tests cover the routing logic.

**Non-Goals:**
- Changing the visual layout or copy of `AddEditExpenseView` itself.
- Introducing a read-only "View Expense" mode distinct from Edit mode (F-2.04 AC: No Edit Mode).
- Any changes to swipe-to-delete, the Add Expense button, or the Budget header row.
- Accessibility label changes beyond what the tap affordance naturally provides (VoiceOver on `Button` wrappers already gains the button trait).

## Decisions

### 1. `AppRoute.expenseDetail(ExpenseItem)` (push) vs reusing `SheetRoute.expense` (sheet)

The current `SheetRoute.expense` case would have the push animate as a sheet over the pushed `BudgetDetailView`. The user's direction is explicit: push. A new `AppRoute` case is the correct structural fit — `AppRoute` is the enum for push destinations, `SheetRoute` is for sheets. Adding `expenseDetail` to `AppRoute` keeps the semantic split clean and matches the existing `budgetDetail` pattern.

**Removing `SheetRoute.expense`**: since it has zero entry points and its behavioural role is superseded by the push path, keeping it would be dead code. Removing it now avoids future confusion about which path is canonical.

### 2. `Button` wrapping in `expenseRow(_:)`

`expenseRow(_:)` currently returns an `ExpenseRowView` directly. The simplest change is to wrap the call in a `Button(action:)` with `.buttonStyle(.plain)` so the row remains visually identical but gains tap semantics. The swipe actions remain on the outermost modifier chain (they are already on `expenseRow`'s return value). SwiftUI applies swipe actions on top of any button style, so no ordering issue arises.

Alternative considered: using `NavigationLink(value:)` directly on the row. This also produces a push and gives the system a disclosure chevron affordance. However, `NavigationLink` forces a persistent disclosure indicator on the right edge of every expense row, which is inappropriate for an editable form destination (it implies drill-into-detail, not edit). A plain `Button` with `router.path.append` matches the `budgetDetail` navigation pattern used by `BudgetsView` (which also uses a Button + `router.path.append` rather than `NavigationLink`). Consistent with existing conventions.

### 3. NavigationStack ownership — remove inner wrapper from `AddEditExpenseView`

`AddEditExpenseView` currently wraps its entire body in `NavigationStack { }`. That wrapper was necessary when the view was designed exclusively for sheet presentation — a sheet presented via `.sheet(item:)` does not inherit the parent `NavigationStack`'s navigation bar, so the view needed its own to host the Cancel and Save toolbar items.

When the view is **pushed** via `navigationDestination`, it runs inside the existing outer `NavigationStack` in `RootView`. Adding its own inner `NavigationStack` produces a nested navigation hierarchy: the outer stack's nav bar (with a back/Cancel button) and the inner stack's nav bar (with Cancel, Save, and the title) appear stacked, resulting in a double navigation bar.

**Decision**: Remove the `NavigationStack { }` wrapper from `AddEditExpenseView.body`. Shift NavigationStack ownership to the caller:

- **Sheet path** (`SheetRoute.addExpense`): `RootView`'s sheet closure wraps `AddEditExpenseView` in `NavigationStack { }`.
- **Push path** (`AppRoute.expenseDetail`): no wrapper needed — the outer `NavigationStack` in `RootView` provides the navigation bar.
- **Previews**: each `#Preview` that currently relies on the inner `NavigationStack` to render the nav bar must add its own `NavigationStack { }` wrapper.

After this change, `dismiss()` from the view's Cancel button:
- In the sheet context: dismisses the sheet (same as before).
- In the push context: pops the view from the outer `NavigationStack` (correct behaviour).

### 4. Testing approach

The existing `BudgetDetailViewActionsTests.swift` tests the reset algorithm at the model/business-logic level — it does not instantiate a view. The tap routing is a view-layer concern: it sets `router.path`. The correct test strategy is to test `Router` state changes directly by simulating the action:

- Construct a `Router` and an `ExpenseItem`.
- Append `.expenseDetail(expense)` to the router path (replicating the button action).
- Assert that `router.path.last == AppRoute.expenseDetail(expense)`.

This tests the routing contract without needing a live SwiftUI view hierarchy. An additional test can assert that `AppRoute.expenseDetail` is `Hashable`/`Equatable` correctly (needed for `NavigationStack` identity).

## Risks / Trade-offs

**[Cancel replaces back chevron]** Users familiar with "back" as a discard-and-return may expect the system back button. Cancel is semantically equivalent here (no save has occurred) but differs visually. → Mitigation: The Cancel label is conventional for editable forms on iOS; the HIG sanctions it. No action needed.

**[`AddEditExpenseView` preview wrappers]** After removing the inner `NavigationStack`, all six existing `#Preview` declarations in `AddEditExpenseView.swift` will lose their nav bar, meaning Cancel and Save buttons will be invisible in Canvas. → Mitigation: wrap each preview body in `NavigationStack { }`.

**[`SheetRoute.expense` removal is breaking within the codebase]** Any code that references `.expense(expense)` on a `SheetRoute` value will not compile after the removal. → Mitigation: The only reference is `RootView.swift` line 33-34, which is replaced by the new `navigationDestination` branch. The test suite does not reference `SheetRoute.expense` directly. Verify with a clean build.

**[Swipe actions + Button wrapper ordering]** If the `Button` wrapper is placed inside the `.swipeActions` modifier chain rather than outside, swipes may be swallowed by the tap gesture. → Mitigation: `expenseRow(_:)` currently applies `.swipeActions` as a modifier on the returned view. The `Button` wraps the `ExpenseRowView` *inside* `expenseRow`, and `.swipeActions` is applied to the `Button`'s outer shell in the same position. SwiftUI's swipe gesture recogniser takes priority over tap on list rows; the ordering is safe.

## Doc alignment

- `docs/product-features-planning.md` F-2.02: the "tap-to-edit on expense rows are out of scope until F-2.04" note must be replaced with a note that tap-to-push is implemented by this change. No new F-x.xx is needed; this is completing F-2.02's deferred work.
- `docs/tech-design-doc.md`: the navigation section describes `AppRoute` and `SheetRoute`. Adding `AppRoute.expenseDetail` and removing `SheetRoute.expense` is a minor update. Will update as part of this change's tasks.
- `docs/main-prd.md`: no changes needed — no global constraints or glossary terms are affected.
