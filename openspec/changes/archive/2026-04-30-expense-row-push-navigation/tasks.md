## 1. Navigation Layer

- [x] 1.1 Add `case expenseDetail(ExpenseItem)` to `AppRoute` in `simple-recurring-budgets/App/AppRoute.swift`; update the doc comment to list both cases.
- [x] 1.2 Remove `case expense(ExpenseItem)` from `SheetRoute` in `simple-recurring-budgets/App/SheetRoute.swift`; update the doc comment.
- [x] 1.3 In `RootView.swift`, add a `case .expenseDetail(let expense): AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))` branch inside `navigationDestination(for: AppRoute.self)`.
- [x] 1.4 In `RootView.swift`, remove the `case .expense(let expense):` branch from the `.sheet(item:)` switch; verify the switch is exhaustive (compiler will confirm).
- [x] 1.5 Update the `RootView.swift` doc comment (currently references `F-2.04 .addExpense / .expense`) to remove the stale `.expense` reference.

## 2. AddEditExpenseView — Remove Inner NavigationStack

- [x] 2.1 In `AddEditExpenseView.swift`, remove the `NavigationStack { }` wrapper from `body` so the view's root is the `ScrollView` (or equivalent content). Keep all modifiers (`.navigationTitle`, `.navigationBarTitleDisplayMode`, `.appBackground`, `.toolbar`, `.onAppear`) as they are — they attach to the content view and propagate to whichever `NavigationStack` is in context.
- [x] 2.2 In `RootView.swift`, wrap the `AddEditExpenseView` in the `.addExpense` sheet branch with `NavigationStack { }` so the sheet retains its nav bar: `NavigationStack { AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget)) }`.
- [x] 2.3 In `AddEditExpenseView.swift`, wrap each `#Preview` body in `NavigationStack { }` so Cancel and Save toolbar items render in Xcode Canvas (all six previews).
- [x] 2.4 Confirm `.confirmationDialog` (delete confirmation) is moved outside the removed `NavigationStack` to remain attached to the view's root — verify it still anchors and presents correctly.

## 3. Budget Detail — Tappable Expense Rows

- [x] 3.1 In `BudgetDetailView+ExpenseSection.swift`, wrap the `ExpenseRowView(…)` inside `expenseRow(_:)` in a `Button(action:) { … }` with `.buttonStyle(.plain)` whose action is `router.path.append(AppRoute.expenseDetail(expense))`.
- [x] 3.2 Verify the `.swipeActions` modifier remains on the *outer* result of `expenseRow(_:)` (i.e., applied after the `Button` and `listRowBackground`), so swipe-to-delete is unaffected.
- [x] 3.3 Confirm that the `router` environment value is accessible inside `expenseRow(_:)` — `BudgetDetailView` already has `@Environment(Router.self) private var router`.

## 4. Tests

- [x] 4.1 In `BudgetDetailViewActionsTests.swift`, add a test `tapExpenseRow_appendsExpenseDetailRoute` that: constructs a `Router`, creates an `ExpenseItem` in an in-memory container, calls `router.path.append(AppRoute.expenseDetail(expense))` (replicating the button action), and asserts `router.path.last == AppRoute.expenseDetail(expense)`.
- [x] 4.2 Add a test `appRoute_expenseDetail_isHashable` that asserts two `AppRoute.expenseDetail` values wrapping the same `ExpenseItem` are equal (required for `NavigationStack` identity tracking).
- [x] 4.3 Add a test `appRoute_expenseDetail_differsByExpense` that asserts `AppRoute.expenseDetail(expenseA) != AppRoute.expenseDetail(expenseB)` for two distinct `ExpenseItem` instances.

## 4. Doc Updates

- [x] 4.1 In `docs/product-features-planning.md`, find the F-2.02 edge-case note "tap-to-edit on expense rows are out of scope until F-2.04" and replace it with a note that tap-to-push via `AppRoute.expenseDetail` is implemented by change `expense-row-push-navigation`.
- [x] 4.2 In `docs/product-features-planning.md`, update the F-2.02 Status line from "Implemented (excluding F-2.04 entry/edit and F-6.01)" to "Implemented (excluding F-6.01). Tap-to-edit implemented by change `expense-row-push-navigation`."
- [x] 4.3 In `docs/product-features-planning.md`, update F-2.02 acceptance criteria to list tap-to-push on expense rows as implemented.
- [x] 4.4 In `docs/tech-design-doc.md`, update the navigation section to reflect `AppRoute` now has two cases (`budgetDetail`, `expenseDetail`) and `SheetRoute` no longer has `expense(ExpenseItem)`.

## 5. Build and Test

- [x] 5.1 Run `make test` (or `bash scripts/test.sh`) and confirm all tests pass with no regressions.
