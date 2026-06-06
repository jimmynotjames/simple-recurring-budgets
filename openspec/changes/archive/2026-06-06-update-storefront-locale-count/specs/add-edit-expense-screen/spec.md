## MODIFIED Requirements

### Requirement: User-visible strings are registered in Localizable.xcstrings under the addEditExpense namespace

Every user-visible string introduced by `AddEditExpenseView` SHALL use `String(localized: "key", defaultValue: "...", comment: "translator context")` (or `Text(LocalizedStringKey)` where idiomatic) with a stable kebab/dot-cased key, an English source default value, and a translator `comment`. Strings SHALL be present in `simple-recurring-budgets/Resources/Localizable.xcstrings` after the build.

The screen-namespaced key prefix SHALL be `addEditExpense.*`. Keys SHALL NOT be reused from unrelated namespaces (e.g., the `addEditBudget.*` keys are budget-screen content and SHALL NOT be reused for expense-screen content even when the English copy coincidentally matches).

The minimum set of keys SHALL include:

- `addEditExpense.title.add`, `addEditExpense.title.existing`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing.addFunds` — sheet titles (the four-way matrix from the navigation-title requirement).
- `addEditExpense.action.cancel`, `addEditExpense.action.save` — toolbar items.
- `addEditExpense.action.delete`, `addEditExpense.action.delete.accessibilityHint` — destructive button label and VoiceOver hint.
- `addEditExpense.deleteConfirmation.title`, `addEditExpense.deleteConfirmation.message`, `addEditExpense.deleteConfirmation.confirm` — destructive confirmation dialog.
- `addEditExpense.section.amount`, `addEditExpense.section.name`, `addEditExpense.section.when` — card section labels.
- `addEditExpense.field.amount.placeholder`, `addEditExpense.field.amount.accessibilityLabel`, `addEditExpense.field.amount.accessibilityLabel.addFunds` — Amount field placeholder and VoiceOver labels (the label flips between expense and add-funds variants based on `viewModel.isAddFunds`).
- `addEditExpense.field.name.placeholder`, `addEditExpense.field.name.accessibilityLabel`, `addEditExpense.field.name.addFundsDefault` — Description field placeholder, VoiceOver label, and the "Add funds" default seeded on toggle-on.
- `addEditExpense.field.date.label` — fallback / explicit label for the date picker.
- `addEditExpense.addFunds.toggle.label`, `addEditExpense.addFunds.toggle.caption` — Add Funds card Toggle label and explanatory caption.

Each key SHALL have a non-empty `comment` providing translator context.

All keys (including the Add Funds keys introduced by F-6.01) SHALL be present in `Localizable.xcstrings` with translations for every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03); the `scripts/translate_catalog/` pipeline SHALL be run as part of any change that adds or modifies keys.

#### Scenario: Every label has a localizable key with a comment

- **WHEN** the app is built
- **THEN** `Localizable.xcstrings` contains one entry per user-visible string introduced by the Add/Edit/View Expense screen, each with a non-empty `comment`

#### Scenario: Sheet titles use the four-key matrix

- **WHEN** the sheet is opened in any of the four combinations of `isEditing × isAddFunds`
- **THEN** the navigation title is sourced from the corresponding key in the matrix (`addEditExpense.title.add`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing`, or `addEditExpense.title.existing.addFunds`), not from a generic top-level English literal

#### Scenario: Expense-screen keys do not reuse addEditBudget keys

- **WHEN** an inspector reads the keys consumed by `AddEditExpenseView`
- **THEN** every key starts with `addEditExpense.`; no key is reused from the `addEditBudget.*` namespace, even when the English copy is identical

#### Scenario: All Add Funds keys are translated to every storefront locale

- **WHEN** the change is merged
- **THEN** the keys `addEditExpense.addFunds.toggle.label`, `addEditExpense.addFunds.toggle.caption`, `addEditExpense.field.name.addFundsDefault`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing.addFunds`, and `addEditExpense.field.amount.accessibilityLabel.addFunds` are present in `Localizable.xcstrings` with translations for every storefront locale listed in F-3.03

### Requirement: Recents UI strings are keyed in Localizable.xcstrings

All user-facing strings introduced by the Recents surface SHALL be registered in `Localizable.xcstrings` under the `addEditExpense.recents.*` namespace, with translator-friendly `comment:` text describing the surface, context, and any interpolated arguments. The keys SHALL be translated to every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03) via the `translate-new-strings` skill before the change ships.

The keys SHALL include at minimum: the section title, the "No matches" placeholder copy, each accessibility label and hint introduced by the accessibility requirement, and any future-tense strings the implementation surfaces.

#### Scenario: All visible Recents strings have localization keys

- **WHEN** an auditor inspects the Recents surface source
- **THEN** no bare-literal `Text("…")` calls appear on user-visible strings under the `addEditExpense.recents.*` surface
- **AND** every string is a `String(localized:defaultValue:comment:)` call (or equivalent) under the `addEditExpense.recents.*` namespace

#### Scenario: Translations exist for every storefront locale

- **WHEN** `python scripts/translate_catalog/check_translations.py` runs after the Recents work lands
- **THEN** the check passes with no missing or stale translations for any `addEditExpense.recents.*` key
