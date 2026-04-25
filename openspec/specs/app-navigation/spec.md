# App navigation

Centralized `Router`/`AppRoute`/`SheetRoute` pattern for type-safe, state-driven navigation in the primary `NavigationStack`. Synced from change `budgets-screen` (2026-04-25).

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
- `case viewExpense(ExpenseItem)`
- `case settings`

`SheetRoute.id` SHALL return `Self` (i.e., the case itself) so that `.sheet(item:)` can distinguish between sheets and animate transitions correctly when the value changes from one case to another.

#### Scenario: SheetRoute is Identifiable for use with .sheet(item:)

- **WHEN** `RootView` declares `.sheet(item: $router.sheet)`
- **THEN** the binding compiles and dismiss/present transitions correctly track the active case (none / `.addBudget` / `.editBudget` / `.addExpense` / `.viewExpense` / `.settings`)

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

While downstream screens (Budget detail, Add/Edit Budget, Add/Edit/View Expense, Settings) are not yet implemented, `RootView` SHALL render placeholder `Text(...)` views for the corresponding `AppRoute` and `SheetRoute` cases. These placeholder strings SHALL be exempt from the localization requirement that applies to production views (per `docs/tech-design-doc.md` §5.1) and SHALL be replaced — string and view — when each destination's owning feature change ships.

#### Scenario: Each route has a placeholder destination

- **WHEN** the app is built before the downstream screens (F-2.02 through F-2.05) ship
- **THEN** every `AppRoute` and `SheetRoute` case is reachable and renders a placeholder `Text` view rather than a navigation error

#### Scenario: Placeholders are replaced with localized real screens by their owning feature changes

- **WHEN** a downstream feature change (e.g. F-2.02 Budget detail) ships
- **THEN** the corresponding placeholder in `RootView` is replaced with the real, fully-localized screen, and the i18n exemption no longer applies to that case
