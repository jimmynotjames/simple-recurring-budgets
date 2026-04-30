# App navigation

## Purpose

Centralized `Router`/`AppRoute`/`SheetRoute` pattern for type-safe, state-driven navigation in the primary `NavigationStack`. Synced from change `budgets-screen` (2026-04-25); expense sheet routing and placeholder exemptions updated for F-2.04 (`add-edit-expense-screen`, 2026-04-29).
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

The system SHALL define `AppRoute` as a `Hashable` enum whose cases enumerate destinations reachable by push navigation within the primary `NavigationStack`. The enum SHALL include at least:

- `case budgetDetail(Budget)` — drill into the expense list for a specific budget.

`AppRoute` cases MAY carry SwiftData `@Model` payloads directly (`Budget`, `ExpenseItem`) when the destination needs a live model reference. Cases SHALL NOT be added speculatively for destinations that have no consumer.

#### Scenario: budgetDetail carries the Budget model

- **WHEN** a row is activated with a specific `Budget`
- **THEN** `AppRoute.budgetDetail(budget)` is appended to the path with that budget instance as its associated value

### Requirement: SheetRoute enumerates sheet presentation destinations

The system SHALL define `SheetRoute` as a `Hashable, Identifiable` enum whose cases enumerate destinations reachable by modal sheet presentation. The enum SHALL include:

- `case addBudget`
- `case editBudget(Budget)`
- `case addExpense(Budget)`
- `case expense(ExpenseItem)` — existing expense (F-2.04: same sheet for view and in-place edit)
- `case settings`

`SheetRoute.id` SHALL return `Self` (i.e., the case itself) so that `.sheet(item:)` can distinguish between sheets and animate transitions correctly when the value changes from one case to another.

#### Scenario: SheetRoute is Identifiable for use with .sheet(item:)

- **WHEN** `RootView` declares `.sheet(item: $router.sheet)`
- **THEN** the binding compiles and dismiss/present transitions correctly track the active case (none / `.addBudget` / `.editBudget` / `.addExpense` / `.expense` / `.settings`)

### Requirement: RootView is the sole NavigationStack host and sheet host

The system SHALL host the primary `NavigationStack` and the single sheet presentation in `RootView`. `RootView` SHALL:

- Bind the navigation path to `$router.path`.
- Embed `BudgetsView` as the stack root.
- Resolve push destinations via `.navigationDestination(for: AppRoute.self) { ... }`.
- Present sheets via `.sheet(item: $router.sheet) { ... }` switching on the active `SheetRoute` case.

`RootView` SHALL NOT introduce new navigation state of its own; all navigation state lives in `Router`.

#### Scenario: RootView routes push destinations via AppRoute

- **WHEN** `router.path` contains a route value
- **THEN** `RootView`'s `navigationDestination(for: AppRoute.self)` resolves it to the corresponding destination view (or a placeholder until the destination ships)

#### Scenario: RootView routes sheets via SheetRoute

- **WHEN** `router.sheet` is non-nil
- **THEN** `RootView`'s `.sheet(item:)` binding presents the corresponding sheet content (or a placeholder until the sheet's screen ships)

### Requirement: Placeholder destinations are exempt from the no-hard-coded-English rule until replaced

While the Budget detail screen is not yet implemented, `RootView` SHALL render a placeholder `Text(...)` view for the corresponding `AppRoute` case. That placeholder string SHALL be exempt from the localization requirement that applies to production views (per `docs/tech-design-doc.md` §5.1) and SHALL be replaced — string and view — when the owning feature change ships.

The Add/Edit Budget sheet (`SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)`) is no longer a placeholder. Both cases SHALL render the real, fully-localized `AddEditBudgetView` (per the `add-edit-budget-screen` capability), and the i18n exemption SHALL NOT apply to them. Concretely, `RootView`'s `.sheet(item:)` switch SHALL resolve `.addBudget` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))` and `.editBudget(let budget)` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))`, where `settings` comes from `@Environment(AppSettings.self)` on `RootView`.

The Settings sheet (`SheetRoute.settings`) is also no longer a placeholder; it has rendered the real `SettingsView` since change `2026-04-28-settings-screen` shipped. The i18n exemption does NOT apply to it.

The Add/Edit/View Expense sheet (`SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)`) is no longer a placeholder; both cases render the real, fully-localized `AddEditExpenseView` (F-2.04). The i18n exemption does NOT apply to them.

The remaining placeholder case — `AppRoute.budgetDetail(Budget)` — keeps the exemption until its owning feature change (F-2.02 Budget detail) ships.

#### Scenario: Each remaining route still has a placeholder destination

- **WHEN** the app is built before the still-pending Budget detail screen (F-2.02) ships
- **THEN** `AppRoute.budgetDetail` renders a placeholder `Text` view rather than a navigation error

#### Scenario: Add Budget sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .addBudget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Add mode, with all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("Add Budget")` placeholder is no longer used

#### Scenario: Edit Budget sheet renders the real screen with the budget seed

- **WHEN** any caller sets `Router.sheet = .editBudget(budget)` for some `Budget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Edit mode, seeded from that `Budget`, with all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("Edit Budget")` placeholder is no longer used

#### Scenario: Add Expense sheet renders the real screen with the budget context

- **WHEN** any caller sets `Router.sheet = .addExpense(budget)` for some `Budget`
- **THEN** `RootView` SHALL render the real `AddEditExpenseView` configured for Add mode, with the in-flight `Budget` available to the VM for attachment on Save, and all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("Add Expense")` placeholder is no longer used

#### Scenario: Existing expense sheet renders the real screen with the expense seed

- **WHEN** any caller sets `Router.sheet = .expense(expense)` for some `ExpenseItem`
- **THEN** `RootView` SHALL render the real `AddEditExpenseView` configured for the existing-expense path (F-2.04 view and in-place edit on one surface), seeded from that `ExpenseItem`, with all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("View Expense")` placeholder is no longer used

#### Scenario: Settings sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .settings`
- **THEN** `RootView` SHALL render the real `SettingsView` (shipped by `2026-04-28-settings-screen`); no placeholder is used and the i18n exemption does not apply

#### Scenario: Placeholders are replaced with localized real screens by their owning feature changes

- **WHEN** the still-pending downstream feature change (F-2.02 Budget detail) ships
- **THEN** the corresponding placeholder in `RootView` is replaced with the real, fully-localized screen, and the i18n exemption no longer applies to that case

