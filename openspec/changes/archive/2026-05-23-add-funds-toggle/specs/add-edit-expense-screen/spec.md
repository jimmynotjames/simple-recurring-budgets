## ADDED Requirements

### Requirement: AddEditExpenseView includes an Add Funds toggle card at the end of the form

The Add/Edit/View Expense screen SHALL render a fourth card — the **Add Funds card** — immediately after the When card and before the Delete button (the Delete button only appears in Edit mode). The card SHALL contain:

- A `Toggle` whose label is the localized key `addEditExpense.addFunds.toggle.label` (en-US `"Add funds"`).
- An explanatory caption immediately below the Toggle row, in `.caption` font with `.secondary` foreground, using the localized key `addEditExpense.addFunds.toggle.caption` (en-US `"Adds to your remaining balance instead of subtracting."`).

The Toggle's tint SHALL be `.accentColor` (matching the carry-over toggle pattern in `AddEditBudgetView.swift:245` and the analytics toggle in `SettingsView.swift:144`). The Toggle SHALL be bound to `AddEditExpenseViewModel.isAddFunds: Bool` (default `false` in Add mode; seeded from the existing row in Edit mode per a separate requirement).

The card SHALL render in both Add and Edit/View mode. In Edit mode the Toggle is interactive — the user MAY flip the type of an existing entry without delete-and-recreate.

The card SHALL use the same `GroupBox` + `Color("CellBackground")` background-style treatment as the other three cards (Amount, Description, When) so it visually reads as a peer.

#### Scenario: Add Funds card renders after the When card

- **WHEN** the sheet is visible in either Add or Edit/View mode
- **THEN** the form shows four cards in order: Amount, Description, When, Add Funds

#### Scenario: Add Funds toggle uses the accent color tint

- **WHEN** the Add Funds toggle is rendered
- **THEN** its `.tint` modifier is set to `.accentColor`

#### Scenario: Add Funds caption is keyed and uses secondary foreground

- **WHEN** the Add Funds card is rendered
- **THEN** the caption text is sourced from `addEditExpense.addFunds.toggle.caption`, uses `.caption` font, and renders in `.secondary` foreground

#### Scenario: Add Funds toggle is editable in Edit mode

- **WHEN** the sheet is opened in Edit mode for an existing `ExpenseItem`
- **THEN** the Add Funds toggle is interactive; the user may flip its state and Save SHALL honor the new state per the Edit-mode sign rule

### Requirement: Toggling Add Funds on tints the amount text and currency prefix with Color.moneySurplus

When `AddEditExpenseViewModel.isAddFunds == true`, the Amount card's currency-prefix `Text` and the numeric `TextField` SHALL render with `.foregroundStyle(Color.moneySurplus)` (matching the green tint used by add-funds rows on the Budget detail screen). When `isAddFunds == false`, the prefix uses `.secondary` and the numeric field uses `.primary` (the existing styling). The transition is driven reactively by the `@Observable` viewmodel and applies without explicit animation.

#### Scenario: Amount text tints green when Add Funds is on

- **WHEN** the user toggles Add Funds on
- **THEN** the currency prefix and the numeric field text render in `Color.moneySurplus`

#### Scenario: Amount text reverts to default colors when Add Funds is off

- **WHEN** the user toggles Add Funds off (from on)
- **THEN** the currency prefix renders in `.secondary` and the numeric field text renders in `.primary`

### Requirement: Toggling Add Funds on seeds the Description field with "Add funds" only when empty

When `AddEditExpenseViewModel.isAddFunds` transitions from `false` to `true`, the viewmodel SHALL inspect the trimmed `name` (`name.trimmingCharacters(in: .whitespacesAndNewlines)`). If and only if the trimmed value is empty, the viewmodel SHALL set `name` to the localized default `addEditExpense.field.name.addFundsDefault` (en-US `"Add funds"`). The seed is one-way:

- Toggling Add Funds off (true → false) SHALL NOT clear `name`.
- Subsequent on transitions (false → true) SHALL NOT overwrite `name` if it is non-empty.

The seed SHALL NOT fire during `init(editing:)` even though that initializer assigns `isAddFunds = expense.isAddFunds` — Swift's `didSet` does not run for initializer-phase assignments, which is the intended behavior here (existing rows already have a user-set description or `nil`, and the seed is reserved for first-time Add-mode entry).

#### Scenario: Toggling on with empty Description seeds "Add funds"

- **WHEN** the user opens Add mode (Description is empty), then toggles Add Funds on
- **THEN** the Description field's draft value becomes `"Add funds"` (sourced from `addEditExpense.field.name.addFundsDefault`)

#### Scenario: Toggling on with non-empty Description does not overwrite

- **WHEN** the user opens Add mode, types `"Refund from Acme"`, then toggles Add Funds on
- **THEN** the Description field's draft value remains `"Refund from Acme"`

#### Scenario: Toggling on with whitespace-only Description seeds "Add funds"

- **WHEN** the user opens Add mode, types `"   "` (whitespace), then toggles Add Funds on
- **THEN** the Description field's draft value becomes `"Add funds"` (whitespace is treated as empty)

#### Scenario: Toggling off does not clear a previously seeded Description

- **WHEN** the user toggles Add Funds on (Description becomes `"Add funds"`), then toggles Add Funds off
- **THEN** the Description field's draft value remains `"Add funds"`

#### Scenario: Re-toggling on after off does not overwrite a non-empty Description

- **WHEN** the user toggles Add Funds on (Description becomes `"Add funds"`), toggles off, then toggles on again
- **THEN** the Description field's draft value remains `"Add funds"` (the second on transition sees a non-empty value and does not re-seed)

#### Scenario: Edit-mode init does not fire the description seed

- **WHEN** `AddEditExpenseViewModel.init(editing: expense)` runs for an `ExpenseItem` with `isAddFunds == true` and `name == nil` (or `name == ""`)
- **THEN** the viewmodel's `name` is the empty string seeded from `expense.name ?? ""`; the `didSet` on `isAddFunds` does NOT fire (initializer-phase assignment); the Description field is NOT auto-filled with `"Add funds"`

## MODIFIED Requirements

### Requirement: Add/Edit/View Expense screen is reachable via SheetRoute.addExpense and AppRoute.expenseDetail

The Add/Edit/View Expense screen SHALL be reachable from exactly two routes:

- `SheetRoute.addExpense(Budget)` — Add mode.
- `AppRoute.expenseDetail(ExpenseItem)` — existing expense (F-2.04: same surface for view and in-place edit), reached via push navigation from `BudgetDetailView`.

`SheetRoute.expense(ExpenseItem)` is removed. No `SheetRoute` case for an existing expense remains.

The navigation title SHALL be sourced from one of four localized keys, selected by the combination of `viewModel.isEditing` and `viewModel.isAddFunds`:

| `isEditing` | `isAddFunds` | Key                                       | en-US         |
| ----------- | ------------ | ----------------------------------------- | ------------- |
| `false`     | `false`      | `addEditExpense.title.add`                | "Add Expense" |
| `false`     | `true`       | `addEditExpense.title.add.addFunds`       | "Add Funds"   |
| `true`      | `false`      | `addEditExpense.title.existing`           | "Expense"     |
| `true`      | `true`       | `addEditExpense.title.existing.addFunds`  | "Add Funds"   |

The Edit-mode add-funds title is intentionally `"Add Funds"` — the same string as the Add-mode title — even though that breaks the action-verb-vs-noun symmetry of the Expense/Add Expense pair. Rationale: `"Funds"` reads awkwardly as a standalone noun-form title, whereas `"Add Funds"` is unambiguous in both Add and Edit contexts. The same word also appears as the Toggle label (`"Add funds"`, lowercased) and the seeded Description default, giving consistent terminology across the surface.

The title SHALL be displayed inline (`.navigationBarTitleDisplayMode(.inline)`). The title SHALL re-evaluate reactively when `isAddFunds` changes mid-session (e.g., when the user toggles the Add Funds card).

#### Scenario: Add mode is presented via SheetRoute.addExpense (sheet)

- **WHEN** a caller sets `Router.sheet = .addExpense(budget)` for some `Budget`
- **THEN** `RootView` SHALL present a `NavigationStack` containing `AddEditExpenseView` configured for Add mode, with the in-flight `Budget` available to the VM for attachment on Save

#### Scenario: Existing expense path is presented via AppRoute.expenseDetail (push)

- **WHEN** the user taps an expense row on `BudgetDetailView`, appending `AppRoute.expenseDetail(expense)` to `router.path`
- **THEN** `RootView`'s `navigationDestination` SHALL push `AddEditExpenseView` configured for Edit/View mode, seeded from that `ExpenseItem`, inside the existing outer `NavigationStack` — no nested `NavigationStack` is introduced

#### Scenario: No nested NavigationStack when pushed

- **WHEN** `AppRoute.expenseDetail(expense)` is resolved by `RootView`'s `navigationDestination`
- **THEN** the resulting screen SHALL have exactly one navigation bar (from the outer `NavigationStack`); a double navigation bar SHALL NOT appear

#### Scenario: Add-mode title flips between Add Expense and Add Funds

- **WHEN** the sheet is open in Add mode with `isAddFunds == false`
- **THEN** the navigation title is sourced from `addEditExpense.title.add` ("Add Expense")

- **WHEN** the user toggles Add Funds on
- **THEN** the navigation title reactively updates to `addEditExpense.title.add.addFunds` ("Add Funds")

#### Scenario: Edit-mode title flips between Expense and Funds

- **WHEN** the screen is pushed in Edit mode for an `ExpenseItem` with `isAddFunds == false`
- **THEN** the navigation title is sourced from `addEditExpense.title.existing` ("Expense")

- **WHEN** the screen is pushed in Edit mode for an `ExpenseItem` with `isAddFunds == true`
- **THEN** the navigation title is sourced from `addEditExpense.title.existing.addFunds` ("Add Funds")

- **WHEN** the user flips the toggle to the opposite state
- **THEN** the navigation title reactively updates to the matching key from the table above

### Requirement: Edit/View mode seeds form fields from the existing ExpenseItem

In Edit/View mode, every editable form field SHALL be seeded from the corresponding field of the `ExpenseItem` passed to the sheet, evaluated **once** at sheet-open time:

- `amount = expense.displayAmount` (absolute value of `expense.amount`; the field shows a positive number even for `isAddFunds` rows whose stored `amount` is negative — the sign is restored on Save per the "Edit-mode Save honors the Add Funds toggle for sign of ExpenseItem.amount" requirement).
- `name = expense.name ?? ""` (empty string when the persisted name is `nil`).
- `date = expense.date`.
- `currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")` (defensive fallback for orphan rows whose parent budget reference is `nil`).
- `isAddFunds = expense.isAddFunds` (so the sheet reflects the persisted sign — the Add Funds toggle reads as on, the amount text tints `Color.moneySurplus`, and the navigation title reads "Add Funds"; this initializer-phase assignment does NOT fire the `isAddFunds` `didSet` so the Description field is NOT auto-seeded with "Add funds" — existing rows keep their stored name).

The view SHALL hold a reference to the passed-in `ExpenseItem` (via the VM's `Mode.edit` associated value) so that Save in Edit/View mode can mutate the same instance and Delete can remove it. Cancel SHALL NOT mutate the `ExpenseItem`.

#### Scenario: Edit/View mode pre-fills from a positive-amount expense

- **WHEN** the sheet is presented for an existing `ExpenseItem` with `amount == 4.50`, `name == "Morning coffee"`, `date == 2026-04-29 09:00`, and `budget.currencyCode == "USD"`
- **THEN** the form shows: Amount `4.50`, Description `"Morning coffee"`, When `2026-04-29 09:00`, currency prefix derived from `"USD"`, Add Funds toggle off, navigation title `"Expense"`

#### Scenario: Edit/View mode pre-fills from a negative-amount (isAddFunds) expense

- **WHEN** the sheet is presented for an existing `ExpenseItem` with `amount == -10` (i.e. an Add Funds row, `isAddFunds == true`)
- **THEN** the Amount field shows `10` (the absolute value); the Add Funds toggle is **on**; the currency prefix and amount text render in `Color.moneySurplus`; the navigation title reads `"Add Funds"`; the underlying `expense.amount` remains `-10` until the user explicitly Saves a change

#### Scenario: Edit/View mode tolerates orphan expenses

- **WHEN** the sheet is presented for an `ExpenseItem` whose `budget` reference is `nil` (e.g. a CloudKit-synced row whose parent budget was deleted on another device)
- **THEN** the form falls back to `currencyCode = Locale.current.currency?.identifier ?? "USD"` rather than crashing; all other fields seed normally; `isAddFunds` is still derived from `expense.isAddFunds`

### Requirement: Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting an `ExpenseItem` (defence in depth if `save(context:)` is invoked without a valid draft).
1. Compute `trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)`. If `trimmedName.isEmpty == true`, the persisted name SHALL be `nil`; otherwise the persisted name SHALL be the trimmed value.
2. Compute `signedAmount = isAddFunds ? -amount! : amount!`. The unwrap is safe because `canSave` guarantees `amount != nil && amount > 0`.
3. Construct an `ExpenseItem(amount: signedAmount, name: trimmedName, date: date)`. The resulting `ExpenseItem.isAddFunds` SHALL equal the viewmodel's `isAddFunds`.
4. Set `expense.budget = budget` (the in-flight `Budget` from the VM's `Mode.add` associated value), establishing the parent relationship before insert.
5. Call `context.insert(expense)`.
6. Call `try? context.save()`.
7. The view dismisses the sheet.

The new expense SHALL appear in the budget's expense list immediately due to SwiftData's reactivity. CloudKit sync SHALL propagate the new row through the existing pipeline; no schema or container changes are introduced.

The `AnalyticsProperty.isAddFunds` property on the `expense_logged` event SHALL reflect the just-inserted `ExpenseItem.isAddFunds` (which equals the viewmodel's `isAddFunds` at Save time).

#### Scenario: Add Save inserts a positive-amount expense when Add Funds is off

- **WHEN** the user activates Save in Add mode with `amount = 5.00`, `name = "Coffee"`, `date = 2026-04-29 10:00`, `isAddFunds = false`, against an in-memory `ModelContainer` containing the in-flight `Budget`
- **THEN** the store contains exactly one new `ExpenseItem` with `amount == 5.00` (positive), `name == "Coffee"`, `date == 2026-04-29 10:00`, `budget` referencing the in-flight `Budget`, and `isAddFunds == false`

#### Scenario: Add Save inserts a negative-amount expense when Add Funds is on

- **WHEN** the user activates Save in Add mode with `amount = 25.00`, `name = "Add funds"`, `date = 2026-04-29 10:00`, `isAddFunds = true`
- **THEN** the inserted `ExpenseItem.amount == -25.00` (sign flipped), `isAddFunds == true`, `name == "Add funds"`

#### Scenario: Add Save trims description whitespace

- **WHEN** the user activates Save in Add mode with `name = "  Coffee  "`
- **THEN** the inserted `ExpenseItem.name` is `"Coffee"` (whitespace trimmed)

#### Scenario: Add Save persists nil description for whitespace-only input

- **WHEN** the user activates Save in Add mode with `name = "   "` (whitespace only) or `name = ""`
- **THEN** the inserted `ExpenseItem.name` is `nil`

#### Scenario: Add Save guards against !canSave

- **WHEN** `save(context:)` is invoked while `canSave == false`
- **THEN** no `ExpenseItem` is inserted, and `context.save()` is not invoked

#### Scenario: Add Save emits expense_logged with correct isAddFunds

- **WHEN** the user activates Save in Add mode with `isAddFunds = true`, `amount = 25.00`
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: true`

- **WHEN** the user activates Save in Add mode with `isAddFunds = false`, `amount = 5.00`
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: false`

### Requirement: Edit-mode Save honors the Add Funds toggle for sign of ExpenseItem.amount

When Save in Edit/View mode detects an amount change (`expense.displayAmount != newAmount`) OR an Add Funds toggle flip (`viewModel.isAddFunds != expense.isAddFunds`), the model write SHALL apply the sign per the viewmodel's current `isAddFunds`:

```swift
expense.amount = viewModel.isAddFunds ? -newAmount : newAmount
```

This is the documented departure from the prior rule (which read `expense.isAddFunds`, the persisted value). Reading the **draft** `isAddFunds` allows the user to flip an entry's type in Edit mode without resorting to delete-and-recreate.

The change comparator SHALL treat an Add Funds toggle flip as a change in its own right — that is, the Save path SHALL detect and persist a toggle flip even when `amount`, `name`, and `date` are unchanged:

- If `viewModel.isAddFunds != expense.isAddFunds`, the model write SHALL flip the sign of `expense.amount` (specifically: `expense.amount = -expense.amount`), mark `expense.lastModified = Date()`, and call `context.save()` exactly once.
- If neither the amount, the toggle, the name, nor the date changed, the Save path SHALL no-op (no mutation, no `lastModified` bump, no `context.save()`).

The user-visible Amount field SHALL remain a non-negative numeric editor regardless of the underlying sign — the sign is encoded by the type of the row (expense vs add-funds), not by the field itself.

The `AnalyticsProperty.isAddFunds` property on the `expense_edited` event SHALL reflect the post-Save value (i.e. `viewModel.isAddFunds`, equal to `expense.isAddFunds` after the write).

#### Scenario: Editing a positive-amount expense persists a positive amount

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = 5.00` (Add Funds toggle off), changes the Amount to `7.50`, and taps Save
- **THEN** the persisted `ExpenseItem.amount == 7.50` (positive), `isAddFunds == false`

#### Scenario: Editing a negative-amount (isAddFunds) expense preserves the negative sign

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = -10` (Add Funds toggle on), changes the Amount to `15` (without touching the toggle), and taps Save
- **THEN** the persisted `ExpenseItem.amount == -15` (sign restored), `isAddFunds == true`

#### Scenario: Flipping the toggle on an existing positive expense

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = 5.00` (Add Funds toggle off), flips the toggle on without changing the amount, and taps Save
- **THEN** the persisted `ExpenseItem.amount == -5.00` (sign flipped), `isAddFunds == true`, `lastModified` is bumped, `context.save()` is called once

#### Scenario: Flipping the toggle on an existing add-funds entry

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = -25.00` (Add Funds toggle on), flips the toggle off without changing the amount, and taps Save
- **THEN** the persisted `ExpenseItem.amount == 25.00` (sign flipped), `isAddFunds == false`, `lastModified` is bumped, `context.save()` is called once

#### Scenario: Flipping the toggle AND changing the amount in a single Save

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = 5.00` (Add Funds toggle off), flips the toggle on AND changes the Amount to `12.00`, and taps Save
- **THEN** the persisted `ExpenseItem.amount == -12.00`, `isAddFunds == true`, `lastModified` is bumped exactly once, `context.save()` is called exactly once

#### Scenario: No-op Save with unchanged toggle and unchanged amount

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = -10` (Add Funds toggle on), makes no changes, and taps Save
- **THEN** the `ExpenseItem.amount` remains `-10`, `isAddFunds` remains `true`, `lastModified` is unchanged, `context.save()` is NOT invoked

#### Scenario: Edit Save emits expense_edited with post-Save isAddFunds

- **WHEN** the user flips the toggle on an existing positive-amount row from off to on and Saves
- **THEN** the `expense_edited` analytics event is fired with `AnalyticsProperty.isAddFunds: true`

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

All keys (including the new ones introduced by this change) SHALL be present in `Localizable.xcstrings` with translations for all 38 App Store storefront locales per `docs/main-prd.md` §6.8 and F-3.03; the `scripts/translate_catalog/` pipeline SHALL be run as part of the change.

#### Scenario: Every label has a localizable key with a comment

- **WHEN** the app is built
- **THEN** `Localizable.xcstrings` contains one entry per user-visible string introduced by the Add/Edit/View Expense screen, each with a non-empty `comment`

#### Scenario: Sheet titles use the four-key matrix

- **WHEN** the sheet is opened in any of the four combinations of `isEditing × isAddFunds`
- **THEN** the navigation title is sourced from the corresponding key in the matrix (`addEditExpense.title.add`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing`, or `addEditExpense.title.existing.addFunds`), not from a generic top-level English literal

#### Scenario: Expense-screen keys do not reuse addEditBudget keys

- **WHEN** an inspector reads the keys consumed by `AddEditExpenseView`
- **THEN** every key starts with `addEditExpense.`; no key is reused from the `addEditBudget.*` namespace, even when the English copy is identical

#### Scenario: All Add Funds keys are translated to all 38 storefront locales

- **WHEN** the change is merged
- **THEN** the keys `addEditExpense.addFunds.toggle.label`, `addEditExpense.addFunds.toggle.caption`, `addEditExpense.field.name.addFundsDefault`, `addEditExpense.title.add.addFunds`, `addEditExpense.title.existing.addFunds`, and `addEditExpense.field.amount.accessibilityLabel.addFunds` are present in `Localizable.xcstrings` with translations for every storefront locale listed in F-3.03

## REMOVED Requirements

### Requirement: Edit-mode Save preserves the sign of ExpenseItem.amount

**Reason**: Replaced by "Edit-mode Save honors the Add Funds toggle for sign of ExpenseItem.amount" — the new requirement reads the draft `isAddFunds` instead of the persisted `expense.isAddFunds`, enabling in-place type flipping. The "preserves" framing was correct only when the toggle didn't exist on the Edit-mode form.

**Migration**: No data migration required. Existing `isAddFunds` rows continue to round-trip with the same sign provided the user doesn't flip the toggle; the new requirement is strictly additive in capability.
