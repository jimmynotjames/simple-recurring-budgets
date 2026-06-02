# App navigation

## Purpose

Centralized `Router`/`AppRoute`/`SheetRoute` pattern for type-safe, state-driven navigation in the primary `NavigationStack`. Synced from change `budgets-screen` (2026-04-25); expense sheet routing and placeholder exemptions updated for F-2.04 (`add-edit-expense-screen`, 2026-04-29); push navigation for expense edit added (`expense-row-push-navigation`, 2026-04-30).
## Requirements
### Requirement: App provides a centralized observable Router for navigation state

The system SHALL provide a `Router` reference type, declared `@Observable` and isolated to `@MainActor`, that owns the app's primary navigation state in two independent properties:

- `path: [AppRoute]` — drives a `NavigationStack`'s pushed destinations.
- `sheet: SheetRoute?` — drives a single modal sheet presented above the navigation stack.

A single `Router` instance SHALL be owned by the app entry point (`simple_recurring_budgetsApp`) as `@State`, injected into the SwiftUI environment via `.environment(router)`. Leaf screens SHALL access the router with `@Environment(Router.self)` to mutate `path` or `sheet` without holding navigation state themselves.

#### Scenario: Router is single, app-scoped, and injected via environment

- **WHEN** the app launches
- **THEN** exactly one `Router` instance is created at app scope and made available to every screen in the SwiftUI environment

#### Scenario: Leaf screens trigger pushes by mutating path

- **WHEN** a leaf screen sets `router.path.append(.<route>)`
- **THEN** the `NavigationStack` hosted by `RootView` pushes the corresponding destination

#### Scenario: Leaf screens trigger sheets by mutating sheet

- **WHEN** a leaf screen sets `router.sheet = .<route>`
- **THEN** the active sheet binding in `RootView` presents the corresponding sheet

### Requirement: AppRoute enumerates push navigation destinations

The system SHALL define `AppRoute` as a `Hashable` enum whose cases enumerate destinations reachable by push navigation within the primary `NavigationStack`. The enum SHALL include:

- `case budgetDetail(Budget)` — drill into the expense list for a specific budget.
- `case expenseDetail(ExpenseItem)` — push into the Add/Edit/View Expense screen for an existing expense (F-2.04 edit path from Budget Detail; no separate view vs edit mode per F-2.04 AC).

`AppRoute` cases MAY carry SwiftData `@Model` payloads directly (`Budget`, `ExpenseItem`) when the destination needs a live model reference. Cases SHALL NOT be added speculatively for destinations that have no consumer.

#### Scenario: budgetDetail carries the Budget model

- **WHEN** a row is activated with a specific `Budget`
- **THEN** `AppRoute.budgetDetail(budget)` is appended to the path with that budget instance as its associated value

#### Scenario: expenseDetail carries the ExpenseItem model

- **WHEN** the user taps an expense row on `BudgetDetailView`
- **THEN** `AppRoute.expenseDetail(expense)` is appended to `router.path` with that `ExpenseItem` instance as its associated value

### Requirement: SheetRoute enumerates sheet presentation destinations

The system SHALL define `SheetRoute` as a `Hashable, Identifiable` enum whose cases enumerate destinations reachable by modal sheet presentation. The enum SHALL include:

- `case addBudget`
- `case editBudget(Budget)`
- `case addExpense(Budget)`
- `case settings`

`SheetRoute.expense(ExpenseItem)` is removed. The existing-expense edit path is now reached via `AppRoute.expenseDetail(ExpenseItem)` (push navigation). `SheetRoute.id` SHALL return `Self` so that `.sheet(item:)` can distinguish between sheets and animate transitions correctly when the value changes.

#### Scenario: SheetRoute is Identifiable for use with .sheet(item:)

- **WHEN** `RootView` declares `.sheet(item: $router.sheet)`
- **THEN** the binding compiles and dismiss/present transitions correctly track the active case (none / `.addBudget` / `.editBudget` / `.addExpense` / `.settings`)

### Requirement: RootView is the sole NavigationStack host and sheet host

The system SHALL host the primary `NavigationStack` and the single sheet presentation in `RootView`. `RootView` SHALL:

- Bind the navigation path to `$router.path`.
- Embed `BudgetsView` as the stack root.
- Resolve push destinations via `.navigationDestination(for: AppRoute.self) { ... }` switching on each `AppRoute` case:
  - `.budgetDetail(let budget)` → `BudgetDetailView(budget: budget)`
  - `.expenseDetail(let expense)` → `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`
- Present sheets via `.sheet(item: $router.sheet) { ... }` switching on the active `SheetRoute` case (`.addBudget`, `.editBudget`, `.addExpense`, `.settings`). The `.expense` case is no longer present in `SheetRoute` and SHALL NOT appear in this switch.

`RootView` SHALL NOT introduce new navigation state of its own; all navigation state lives in `Router`.

#### Scenario: RootView routes expenseDetail push destination

- **WHEN** `router.path` contains `AppRoute.expenseDetail(expense)` for some `ExpenseItem`
- **THEN** `RootView`'s `navigationDestination(for: AppRoute.self)` resolves it to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`, presenting the screen as a push within the `NavigationStack`

#### Scenario: RootView routes push destinations via AppRoute

- **WHEN** `router.path` contains a route value
- **THEN** `RootView`'s `navigationDestination(for: AppRoute.self)` resolves it to the corresponding destination view

#### Scenario: RootView routes sheets via SheetRoute

- **WHEN** `router.sheet` is non-nil
- **THEN** `RootView`'s `.sheet(item:)` binding presents the corresponding sheet content

### Requirement: Placeholder destinations are exempt from the no-hard-coded-English rule until replaced

All `AppRoute` and `SheetRoute` cases SHALL resolve to real, fully-localized screens — no placeholder bodies remain. The Add/Edit Budget sheet (`SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)`) renders the real, fully-localized `AddEditBudgetView`. The Settings sheet (`SheetRoute.settings`) renders the real `SettingsView`. The Add Expense sheet (`SheetRoute.addExpense(Budget)`) renders the real `AddEditExpenseView` in Add mode. The existing-expense edit path (`AppRoute.expenseDetail(ExpenseItem)`) renders `AddEditExpenseView` in Edit mode via push navigation; it is no longer a sheet.

All placeholder exemptions have been retired. There are no remaining `AppRoute` or `SheetRoute` cases with placeholder bodies.

#### Scenario: Each route resolves to a real, localized screen

- **WHEN** any `AppRoute` or `SheetRoute` case is activated
- **THEN** `RootView` resolves it to the real, fully-localized screen; no `Text("…")` placeholder is used for any currently-shipping case

#### Scenario: Add Budget sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .addBudget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Add mode, with all user-visible strings sourced from `Localizable.xcstrings`

#### Scenario: Edit Budget sheet renders the real screen with the budget seed

- **WHEN** any caller sets `Router.sheet = .editBudget(budget)` for some `Budget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Edit mode, seeded from that `Budget`, with all user-visible strings sourced from `Localizable.xcstrings`

#### Scenario: Add Expense sheet renders the real screen with the budget context

- **WHEN** any caller sets `Router.sheet = .addExpense(budget)` for some `Budget`
- **THEN** `RootView` SHALL render the real `AddEditExpenseView` configured for Add mode wrapped in a `NavigationStack`, with the in-flight `Budget` available to the VM for attachment on Save, and all user-visible strings sourced from `Localizable.xcstrings`

#### Scenario: Settings sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .settings`
- **THEN** `RootView` SHALL render the real `SettingsView`; no placeholder is used and the i18n exemption does not apply

### Requirement: Root view hosts the rating-prompt presenter

The root view SHALL host the rating-prompt presenter, which reads `@Environment(\.requestReview)` and, when the rating-prompt coordinator has a pending request and the scene phase is active, requests a review via the native API, instructs the coordinator to record the requested version, and clears the pending signal. The presenter MUST be hosted once at the root so it functions regardless of which screen the user returns to after dismissing the Add Expense sheet, and MUST NOT present any custom rating UI.

#### Scenario: Pending request is presented when the scene is active

- **WHEN** the coordinator's request-pending signal is set and the scene phase becomes (or is) active
- **THEN** the root presenter requests a review via `requestReview`
- **AND** the coordinator records the current app version and clears the pending signal

#### Scenario: Presenter is inert without a pending request

- **WHEN** there is no pending request
- **THEN** the root presenter takes no action and presents no UI

