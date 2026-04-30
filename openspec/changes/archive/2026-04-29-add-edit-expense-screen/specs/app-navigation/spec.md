<!--
  This delta MODIFIES the `app-navigation` capability. It does not add any
  new requirement; it narrows the existing "Placeholder destinations are
  exempt from the no-hard-coded-English rule until replaced" requirement so
  that the `.addExpense(Budget)` and `.expense(ExpenseItem)` cases —
  which this change replaces with the real, fully-localized
  `AddEditExpenseView` — are no longer exempt.

  After this change, the only remaining placeholder case is
  `AppRoute.budgetDetail(Budget)`, which keeps the exemption until the
  F-2.02 (Budget detail) change ships.
-->

## MODIFIED Requirements

### Requirement: Placeholder destinations are exempt from the no-hard-coded-English rule until replaced

While downstream screens (Budget detail) are not yet implemented, `RootView` SHALL render placeholder `Text(...)` views for the corresponding `AppRoute` cases. These placeholder strings SHALL be exempt from the localization requirement that applies to production views (per `docs/tech-design-doc.md` §5.1) and SHALL be replaced — string and view — when each destination's owning feature change ships.

The Add/Edit Budget sheet (`SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)`) is no longer a placeholder. Both cases SHALL render the real, fully-localized `AddEditBudgetView` (per the `add-edit-budget-screen` capability), and the i18n exemption SHALL NOT apply to them. Concretely, `RootView`'s `.sheet(item:)` switch SHALL resolve `.addBudget` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))` and `.editBudget(let budget)` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))`, where `settings` comes from `@Environment(AppSettings.self)` on `RootView`.

The Add/Edit/View Expense sheet (`SheetRoute.addExpense(Budget)` and `SheetRoute.expense(ExpenseItem)`) is no longer a placeholder. Both cases SHALL render the real, fully-localized `AddEditExpenseView` (per the `add-edit-expense-screen` capability), and the i18n exemption SHALL NOT apply to them. Concretely, `RootView`'s `.sheet(item:)` switch SHALL resolve `.addExpense(let budget)` to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))` and `.expense(let expense)` to `AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: expense))`.

The Settings sheet (`SheetRoute.settings`) is also no longer a placeholder; it has rendered the real `SettingsView` since change `2026-04-28-settings-screen` shipped. The i18n exemption does NOT apply to it.

The remaining placeholder case — `AppRoute.budgetDetail(Budget)` — keeps the exemption until its owning feature change (F-2.02) ships.

#### Scenario: Each remaining route still has a placeholder destination

- **WHEN** the app is built before the still-pending downstream screen (F-2.02 Budget detail) ships
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
