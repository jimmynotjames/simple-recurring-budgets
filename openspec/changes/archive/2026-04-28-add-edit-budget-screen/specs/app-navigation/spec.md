<!--
  This delta MODIFIES the `app-navigation` capability. It does not add any
  new requirement; it narrows the existing "Placeholder destinations are
  exempt from the no-hard-coded-English rule until replaced" requirement so
  that the `.addBudget` and `.editBudget(Budget)` cases — which this change
  replaces with the real, fully-localized `AddEditBudgetView` — are no
  longer exempt.

  Note: the prior change `2026-04-28-settings-screen` shipped the real
  `SettingsView` for `SheetRoute.settings` but did NOT update this
  requirement in `openspec/specs/app-navigation/spec.md` to reflect that
  `.settings` is no longer a placeholder. Because a `MODIFIED Requirements`
  block must contain the FULL updated content of the requirement, this
  delta also drops `.settings` from the remaining-placeholder list to
  reflect the current real-world wiring; that is a docs-drift fixup
  picked up cleanly as part of this change and is not a behavioural change.
  The remaining placeholder cases after this change are
  `AppRoute.budgetDetail(Budget)`, `SheetRoute.addExpense(Budget)`, and
  `SheetRoute.viewExpense(ExpenseItem)`.
-->

## MODIFIED Requirements

### Requirement: Placeholder destinations are exempt from the no-hard-coded-English rule until replaced

While downstream screens (Budget detail, Add/Edit/View Expense) are not yet implemented, `RootView` SHALL render placeholder `Text(...)` views for the corresponding `AppRoute` and `SheetRoute` cases. These placeholder strings SHALL be exempt from the localization requirement that applies to production views (per `docs/tech-design-doc.md` §5.1) and SHALL be replaced — string and view — when each destination's owning feature change ships.

The Add/Edit Budget sheet (`SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)`) is no longer a placeholder. Both cases SHALL render the real, fully-localized `AddEditBudgetView` (per the `add-edit-budget-screen` capability), and the i18n exemption SHALL NOT apply to them. Concretely, `RootView`'s `.sheet(item:)` switch SHALL resolve `.addBudget` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))` and `.editBudget(let budget)` to `AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))`, where `settings` comes from `@Environment(AppSettings.self)` on `RootView`.

The Settings sheet (`SheetRoute.settings`) is also no longer a placeholder; it has rendered the real `SettingsView` since change `2026-04-28-settings-screen` shipped. The i18n exemption does NOT apply to it.

The remaining placeholder cases — `AppRoute.budgetDetail(Budget)`, `SheetRoute.addExpense(Budget)`, and `SheetRoute.viewExpense(ExpenseItem)` — keep the exemption until their owning feature changes (F-2.02, F-2.04) ship.

#### Scenario: Each remaining route still has a placeholder destination

- **WHEN** the app is built before the still-pending downstream screens (F-2.02 Budget detail, F-2.04 Add/Edit/View Expense) ship
- **THEN** `AppRoute.budgetDetail`, `SheetRoute.addExpense`, and `SheetRoute.viewExpense` each render a placeholder `Text` view rather than a navigation error

#### Scenario: Add Budget sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .addBudget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Add mode, with all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("Add Budget")` placeholder is no longer used

#### Scenario: Edit Budget sheet renders the real screen with the budget seed

- **WHEN** any caller sets `Router.sheet = .editBudget(budget)` for some `Budget`
- **THEN** `RootView` SHALL render the real `AddEditBudgetView` configured for Edit mode, seeded from that `Budget`, with all user-visible strings sourced from `Localizable.xcstrings`; the previous `Text("Edit Budget")` placeholder is no longer used

#### Scenario: Settings sheet renders the real screen

- **WHEN** any caller sets `Router.sheet = .settings`
- **THEN** `RootView` SHALL render the real `SettingsView` (shipped by `2026-04-28-settings-screen`); no placeholder is used and the i18n exemption does not apply

#### Scenario: Placeholders are replaced with localized real screens by their owning feature changes

- **WHEN** a still-pending downstream feature change (F-2.02 Budget detail, F-2.04 Add/Edit/View Expense) ships
- **THEN** the corresponding placeholder in `RootView` is replaced with the real, fully-localized screen, and the i18n exemption no longer applies to that case
