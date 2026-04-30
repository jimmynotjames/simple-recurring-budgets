## ADDED Requirements

### Requirement: Add/Edit/View Expense screen is a single sheet for both create and edit modes

The system SHALL present a single SwiftUI sheet, `AddEditExpenseView`, used for both creating a new `ExpenseItem` (Add mode) and editing an existing `ExpenseItem` (Edit/View mode). Per F-2.04, the screen does NOT distinguish between Edit and View — Edit mode IS the View mode and there is no read-only toggle.

The sheet SHALL be presented from the existing `Router.sheet` mechanism via two existing `SheetRoute` cases:

- `SheetRoute.addExpense(Budget)` — Add mode.
- `SheetRoute.expense(ExpenseItem)` — existing expense (F-2.04: same surface for view and in-place edit).

No new `SheetRoute` cases beyond the two expense routes SHALL be introduced. The existing-expense route is `SheetRoute.expense(ExpenseItem)` (neutral name aligned with F-2.04: one surface for view and in-place edit).

The sheet's navigation title SHALL read the localized string `"Add Expense"` (key `addEditExpense.title.add`) in Add mode and a neutral title for an existing row (key `addEditExpense.title.existing`; English string catalog value `"Expense"`) on the existing-expense path. The title SHALL be displayed inline (`.navigationBarTitleDisplayMode(.inline)`).

The sheet SHALL expose two toolbar items: a leading `Cancel` button (key `addEditExpense.action.cancel`) that dismisses without persisting any changes, and a trailing `Save` button (key `addEditExpense.action.save`) whose enablement follows the validation rule documented in the "Save is enabled only when amount is strictly positive" requirement.

#### Scenario: Add mode is presented via SheetRoute.addExpense

- **WHEN** a caller sets `Router.sheet = .addExpense(budget)` for some `Budget`
- **THEN** `RootView` SHALL present `AddEditExpenseView` configured for Add mode, with the in-flight `Budget` available to the VM for attachment on Save

#### Scenario: Existing expense path is presented via SheetRoute.expense

- **WHEN** a caller sets `Router.sheet = .expense(expense)` for some `ExpenseItem`
- **THEN** `RootView` SHALL present `AddEditExpenseView` configured for the existing-expense path, seeded from that `ExpenseItem`

#### Scenario: Sheet exposes Cancel and Save toolbar items

- **WHEN** the sheet is visible in either Add or Edit/View mode
- **THEN** the navigation bar SHALL show a leading Cancel button and a trailing Save button (localized via `addEditExpense.action.cancel` and `addEditExpense.action.save`); no other toolbar items SHALL be present on this sheet

### Requirement: Form fields are Amount, Description (optional), and When (date/time)

The Add/Edit/View Expense screen SHALL collect exactly three user-editable fields, organised into three cards (Amount, Description, When) per the user-approved layout. Fields SHALL always be directly editable in place — there SHALL NOT be any "edit mode" toggle that switches between read-only and editable states (per F-2.04 AC).

The fields are:

- **Amount** (`Decimal?` in `AddEditExpenseViewModel`) — bound to a `TextField` using `TextField(_:value:format:)` with a custom `ParseableFormatStyle` whose `FormatInput` is `Decimal?`, so an empty field maps to `nil` (blank default in Add mode) and entered text parses to a `Decimal` using the user's current `Locale`. Display formatting for non-`nil` values SHALL use `.number.precision(.fractionLength(0...2))`. Placeholder `"0"` (key `addEditExpense.field.amount.placeholder`). Keyboard type SHALL be `.decimalPad`. A currency prefix `Text` SHALL be displayed to the leading edge of the `TextField` in the same `HStack`; the prefix content is derived from `settings.currencyDisplay.prefix(for: viewModel.currencyCode)` and SHALL update reactively whenever `settings.currencyDisplay` changes. Accessibility label `"Expense amount"` (key `addEditExpense.field.amount.accessibilityLabel`). The view SHALL read `AppSettings` via `@Environment(AppSettings.self)`; the VM SHALL NOT store `AppSettings`.
- **Description** (`String` in the VM, persisted as `String?`) — bound to a single-line `TextField` in the Description card. Placeholder `"e.g. Coffee"` (key `addEditExpense.field.name.placeholder`). Section label `"Description (optional)"` (key `addEditExpense.section.name`). Accessibility label `"Expense description"` (key `addEditExpense.field.name.accessibilityLabel`). Per F-2.04 AC, the description is optional — Save SHALL NOT be gated on it being non-empty.
- **When** (`Date`) — bound to a `DatePicker` with `displayedComponents: [.date, .hourAndMinute]` and `.datePickerStyle(.compact)`. Section label `"When"` (key `addEditExpense.section.when`). The picker's own label is hidden (`.labelsHidden()`) and provided via the section header.

Section labels for the three cards use keys `addEditExpense.section.amount`, `addEditExpense.section.name`, and `addEditExpense.section.when`.

The currency code shown in the Amount prefix SHALL be derived as follows:

- In Add mode, from the in-flight `Budget.currencyCode`.
- In Edit/View mode, from `expense.budget?.currencyCode`, falling back to `Locale.current.currency?.identifier ?? "USD"` if the parent budget reference is `nil` (defensive against orphan rows synced from another device).

The currency code SHALL be stored on the VM as a `let` (immutable for the lifetime of the sheet); the user CANNOT change the per-expense currency from this screen.

#### Scenario: All three fields render in their cards

- **WHEN** the sheet is visible in either Add or Edit/View mode
- **THEN** the screen displays three cards in this order: Amount, Description, When; the Amount card contains the currency-prefix text and the numeric field; the Description card contains the single-line text field; the When card contains the compact date/time picker

#### Scenario: Amount currency prefix matches AppSettings.currencyDisplay

- **WHEN** `settings.currencyDisplay == .symbol` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"$"` as a leading prefix text before the numeric field

- **WHEN** `settings.currencyDisplay == .code` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD"` as a leading prefix text

- **WHEN** `settings.currencyDisplay == .codeAndSymbol` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD $"` as a leading prefix text

#### Scenario: Currency prefix updates live when settings change

- **WHEN** the user changes `AppSettings.currencyDisplay` while the sheet is open
- **THEN** the prefix text in the Amount card updates immediately to reflect the new preference without dismissing or reloading the sheet

#### Scenario: Amount field parses optional Decimal with locale-aware parsing

- **WHEN** the user clears the Amount `TextField` or leaves it empty in Add mode
- **THEN** the draft `amount` is `nil` (blank), not `0`

- **WHEN** the user enters a number in the Amount `TextField`
- **THEN** the parse strategy reads the text using `Decimal(string:locale:)` with `.current`, so locale-appropriate decimal separators apply; successful parse yields `Decimal`; the underlying VM state remains `Decimal?` (entered value or `nil` when empty)

- **WHEN** the user enters an unparseable string (e.g. via paste)
- **THEN** the parse strategy throws `CocoaError(.formatting)` and the field rejects the input

#### Scenario: Description field accepts arbitrary text including empty

- **WHEN** the user types nothing in the Description field
- **THEN** the draft `name` remains the empty string, the persisted value (on Save) is `nil`, and Save is NOT gated on the field

- **WHEN** the user types `"   Coffee   "` in the Description field
- **THEN** the draft `name` is the literal user-entered string `"   Coffee   "`, but on Save the persisted `ExpenseItem.name` is the trimmed value `"Coffee"`

- **WHEN** the user types only whitespace in the Description field
- **THEN** on Save the persisted `ExpenseItem.name` is `nil` (whitespace-only collapses to no description)

#### Scenario: When field defaults to current date and time in Add mode

- **WHEN** the sheet opens in Add mode
- **THEN** the When picker is initialised to `Date()` (current wall-clock time at sheet construction) and is freely editable by the user

#### Scenario: When field is seeded from the existing expense in Edit mode

- **WHEN** the sheet opens in Edit/View mode for an existing `ExpenseItem`
- **THEN** the When picker is initialised to `expense.date`, with date and time components both reflecting the stored value

### Requirement: Add mode auto-focuses the Amount field; Edit/View mode does not

In Add mode, the Amount `TextField` SHALL receive keyboard focus automatically when the sheet appears (via `@FocusState` plus `.onAppear`), so the software keyboard appears immediately and the user can begin typing without an extra tap. In Edit/View mode, no field SHALL receive automatic focus; the user must tap to begin editing.

This SHALL be enforced by gating the focus assignment on `viewModel.isEditing == false`:

```swift
.onAppear {
  if !viewModel.isEditing {
    isAmountFocused = true
  }
}
```

#### Scenario: Add mode auto-focuses the Amount field

- **WHEN** the sheet opens in Add mode
- **THEN** the Amount `TextField` receives keyboard focus immediately and the software keyboard is presented

#### Scenario: Edit/View mode does not auto-focus any field

- **WHEN** the sheet opens in Edit/View mode for an existing `ExpenseItem`
- **THEN** no field receives automatic focus; the keyboard is NOT auto-presented; the user must tap a field to begin editing

### Requirement: Add mode seeds blank-amount, empty-description, current-date defaults

In Add mode, the form fields SHALL be initialised at sheet-open time as follows, all evaluated **once** when `AddEditExpenseViewModel.init(adding:)` runs:

- `amount = nil` (no default amount — the Amount field is blank until the user enters a positive value).
- `name = ""` (empty string — the Description `TextField` displays the placeholder; the persisted value is `nil` if the user does not type anything).
- `date = Date()` (current wall-clock time).
- `currencyCode = budget.currencyCode` (matches the parent budget's currency for the prefix display).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` or the parent `Budget` after the sheet opens; the user can edit any field manually before saving.

#### Scenario: Add mode opens with documented defaults

- **WHEN** the sheet opens in Add mode for a `Budget` with `currencyCode == "USD"`
- **THEN** the form shows: amount field blank (draft `nil`), description field empty (placeholder visible), When picker at the current date and time, currency prefix derived from `"USD"` and the user's `currencyDisplay` preference; Save is disabled because `amount` is `nil`

### Requirement: Edit/View mode seeds form fields from the existing ExpenseItem

In Edit/View mode, every editable form field SHALL be seeded from the corresponding field of the `ExpenseItem` passed to the sheet, evaluated **once** at sheet-open time:

- `amount = expense.displayAmount` (absolute value of `expense.amount`; the field shows a positive number even for `isAddFunds` rows whose stored `amount` is negative — the sign is restored on Save per the "Edit-mode Save preserves the sign of ExpenseItem.amount" requirement).
- `name = expense.name ?? ""` (empty string when the persisted name is `nil`).
- `date = expense.date`.
- `currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")` (defensive fallback for orphan rows whose parent budget reference is `nil`).

The view SHALL hold a reference to the passed-in `ExpenseItem` (via the VM's `Mode.edit` associated value) so that Save in Edit/View mode can mutate the same instance and Delete can remove it. Cancel SHALL NOT mutate the `ExpenseItem`.

#### Scenario: Edit/View mode pre-fills from a positive-amount expense

- **WHEN** the sheet is presented for an existing `ExpenseItem` with `amount == 4.50`, `name == "Morning coffee"`, `date == 2026-04-29 09:00`, and `budget.currencyCode == "USD"`
- **THEN** the form shows: Amount `4.50`, Description `"Morning coffee"`, When `2026-04-29 09:00`, currency prefix derived from `"USD"`

#### Scenario: Edit/View mode pre-fills from a negative-amount (isAddFunds) expense

- **WHEN** the sheet is presented for an existing `ExpenseItem` with `amount == -10` (i.e. an Add Funds row, `isAddFunds == true`)
- **THEN** the Amount field shows `10` (the absolute value); the underlying `expense.amount` remains `-10` until the user explicitly Saves a change

#### Scenario: Edit/View mode tolerates orphan expenses

- **WHEN** the sheet is presented for an `ExpenseItem` whose `budget` reference is `nil` (e.g. a CloudKit-synced row whose parent budget was deleted on another device)
- **THEN** the form falls back to `currencyCode = Locale.current.currency?.identifier ?? "USD"` rather than crashing; all other fields seed normally

### Requirement: Save is enabled only when amount is strictly positive

The Save toolbar button SHALL be enabled if and only if `(amount ?? 0) > 0`. Specifically:

- `amount == nil` (blank field) → Save disabled.
- `amount == 0` → Save disabled.
- `amount < 0` → Save disabled (unreachable from the `.decimalPad` keyboard, but the guard is canonical).
- `amount > 0` → Save enabled, regardless of whether the description is empty.

When the condition fails, the Save button SHALL be disabled with the system disabled appearance; no inline error text is displayed.

The Save button SHALL render with `.fontWeight(.semibold)` to match the Add/Edit Budget pattern.

#### Scenario: Blank amount disables Save

- **WHEN** the user opens Add mode and has not entered an amount (`amount == nil`)
- **THEN** the Save button is disabled

#### Scenario: Zero amount disables Save

- **WHEN** the user types `0` in the Amount field
- **THEN** the Save button is disabled

#### Scenario: Negative amount disables Save

- **WHEN** the VM's `amount` is set to a negative `Decimal` (e.g. by a programmatic test)
- **THEN** the Save button is disabled

#### Scenario: Positive amount enables Save regardless of description

- **WHEN** the VM's `amount > 0` and the description is empty
- **THEN** the Save button is enabled

- **WHEN** the VM's `amount > 0` and the description is non-empty
- **THEN** the Save button is enabled

### Requirement: VM exposes save and delete methods that take ModelContext at the call site

The `AddEditExpenseViewModel` SHALL expose:

- `func save(context: ModelContext)` — performs the Add or Edit branch documented in subsequent requirements.
- `func delete(context: ModelContext)` — performs the Edit-mode delete or no-ops in Add mode.

The view SHALL read `@Environment(\.modelContext)` and invoke `viewModel.save(context: context)` / `viewModel.delete(context: context)` from inside `body`, then call `dismiss()`. The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation.

The save and delete bodies SHALL NOT consult `AppSettings` — `AppSettings` is read only by the view (for the currency-prefix display), per `docs/tech-design-doc.md` §2.1: "Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant)" — for these bodies, `AppSettings` is not relevant.

The VM SHALL NOT have any stored property of type `ModelContext` and SHALL NOT have any stored property of type `AppSettings`.

#### Scenario: Save method signature does not include AppSettings

- **WHEN** `AddEditExpenseViewModel.save(...)` is inspected
- **THEN** its signature SHALL be `func save(context: ModelContext)`; `AppSettings` SHALL NOT be a parameter

#### Scenario: Delete method signature does not include AppSettings

- **WHEN** `AddEditExpenseViewModel.delete(...)` is inspected
- **THEN** its signature SHALL be `func delete(context: ModelContext)`; `AppSettings` SHALL NOT be a parameter

#### Scenario: VM does not own ModelContext or AppSettings

- **WHEN** `AddEditExpenseViewModel` is inspected
- **THEN** it has no stored property of type `ModelContext`, no stored property of type `AppSettings`, and no `init` taking either type

### Requirement: Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting an `ExpenseItem` (defence in depth if `save(context:)` is invoked without a valid draft).
1. Compute `trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)`. If `trimmedName.isEmpty == true`, the persisted name SHALL be `nil`; otherwise the persisted name SHALL be the trimmed value.
2. Construct an `ExpenseItem(amount: amount!, name: trimmedName, date: date)`. The unwrap is safe because `canSave` guarantees `amount != nil && amount > 0`.
3. Set `expense.budget = budget` (the in-flight `Budget` from the VM's `Mode.add` associated value), establishing the parent relationship before insert.
4. Call `context.insert(expense)`.
5. Call `try? context.save()`.
6. The view dismisses the sheet.

The new expense SHALL appear in the budget's expense list immediately due to SwiftData's reactivity. CloudKit sync SHALL propagate the new row through the existing pipeline; no schema or container changes are introduced.

The inserted `ExpenseItem.amount` in Add mode SHALL be non-negative (the user has no Add Funds affordance on this screen yet — F-6.01's future change will introduce that toggle).

#### Scenario: Add Save inserts exactly one expense attached to the budget

- **WHEN** the user activates Save in Add mode with `amount = 5.00`, `name = "Coffee"`, `date = 2026-04-29 10:00`, against an in-memory `ModelContainer` containing the in-flight `Budget`
- **THEN** the store contains exactly one new `ExpenseItem` with `amount == 5.00`, `name == "Coffee"`, `date == 2026-04-29 10:00`, `budget` referencing the in-flight `Budget`, and `amount > 0`

#### Scenario: Add Save trims description whitespace

- **WHEN** the user activates Save in Add mode with `name = "  Coffee  "`
- **THEN** the inserted `ExpenseItem.name` is `"Coffee"` (whitespace trimmed)

#### Scenario: Add Save persists nil description for whitespace-only input

- **WHEN** the user activates Save in Add mode with `name = "   "` (whitespace only) or `name = ""`
- **THEN** the inserted `ExpenseItem.name` is `nil`

#### Scenario: Add Save guards against !canSave

- **WHEN** `save(context:)` is invoked while `canSave == false`
- **THEN** no `ExpenseItem` is inserted, and `context.save()` is not invoked

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit/View mode, the system SHALL compare each editable field on the existing `ExpenseItem` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `ExpenseItem`. The system SHALL set `ExpenseItem.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `lastModified` and SHALL NOT call `context.save()`. After mutating any field, the system SHALL call `try? context.save()` and dismiss the sheet.

The fields compared are:

- **Amount**: compared as `expense.displayAmount != newAmount` (where `newAmount` is the unwrapped draft `amount`). The comparison is against the absolute value to mirror how the field is seeded (Edit mode shows the absolute value for `isAddFunds` rows). The model write applies the sign per the "Edit-mode Save preserves the sign of ExpenseItem.amount" requirement.
- **Description**: compared as `expense.name != trimmedName` where `trimmedName` is computed identically to Add mode (whitespace-trimmed; empty-after-trim collapses to `nil`).
- **Date**: compared via `Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute)`. Sub-minute differences SHALL NOT count as a change (the picker's resolution is `.hourAndMinute`, so smaller deltas are not user-visible).

The system SHALL NOT touch any other persisted field of `ExpenseItem` (notably `expenseType`, `createdAt`, `id`, the `budget` relationship).

#### Scenario: No-op Save does not bump lastModified

- **WHEN** the user opens the sheet for an existing `ExpenseItem`, makes no changes, and taps Save
- **THEN** the `ExpenseItem.lastModified` is unchanged from before the sheet was opened, and no `context.save()` write occurs as a result of this Save

#### Scenario: Single-field change updates lastModified once

- **WHEN** the user changes only the description on an existing `ExpenseItem` and taps Save
- **THEN** the `ExpenseItem.name` is updated, `lastModified` is set to a `Date()` greater than its prior value, and no other persisted field (`amount`, `date`, `expenseType`, `createdAt`) is mutated

#### Scenario: Multi-field change is batched into a single context.save()

- **WHEN** the user changes both the description and the amount on an existing `ExpenseItem` and taps Save
- **THEN** both fields are written, `lastModified` is set to a single `Date()` value, and `context.save()` is called exactly once for the whole edit

#### Scenario: Sub-minute date change is treated as no-op

- **WHEN** the user opens the sheet, the picker emits a sub-minute drift on the Date (e.g. seconds component shifts), and the user taps Save without any other change
- **THEN** the `ExpenseItem.lastModified` is unchanged and `context.save()` is NOT invoked as a result of this Save

#### Scenario: Edit-mode field comparator uses displayAmount for negative rows

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = -10` (an `isAddFunds` row), the Amount field shows `10`, and the user taps Save without changing the field
- **THEN** the change comparator treats the amount as unchanged (because `displayAmount == 10 == newAmount`), so `lastModified` is NOT bumped and `expense.amount` remains `-10`

### Requirement: Edit-mode Save preserves the sign of ExpenseItem.amount

When Save in Edit/View mode detects an amount change (`expense.displayAmount != newAmount`), the model write SHALL preserve the sign of the stored `ExpenseItem.amount`:

```swift
expense.amount = expense.isAddFunds ? -newAmount : newAmount
```

This ensures that an `ExpenseItem` whose underlying `amount` is negative (an Add Funds row, per F-6.01) does NOT silently flip its sign on the user's first edit. Add mode is unaffected by this requirement (Add mode unconditionally inserts a non-negative `amount`; F-6.01's future change will introduce the Add Funds toggle in Add mode).

The user-visible Amount field SHALL remain a non-negative numeric editor regardless of the underlying sign — the sign is encoded by the type of the row (expense vs add-funds), not by the field itself.

#### Scenario: Editing a positive-amount expense persists a positive amount

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = 5.00`, changes the Amount to `7.50`, and taps Save
- **THEN** the persisted `ExpenseItem.amount == 7.50` (positive)

#### Scenario: Editing a negative-amount (isAddFunds) expense preserves the negative sign

- **WHEN** the user opens the sheet for an `ExpenseItem` with `amount = -10` (an Add Funds row, `isAddFunds == true`), changes the Amount to `15`, and taps Save
- **THEN** the persisted `ExpenseItem.amount == -15` (sign restored), `isAddFunds` remains `true`

#### Scenario: Add-mode Save unconditionally inserts a non-negative amount

- **WHEN** the user activates Save in Add mode with `amount = 5.00`
- **THEN** the inserted `ExpenseItem.amount == 5.00`; there is no UI on this screen for entering a negative (Add Funds) value

### Requirement: Cancel dismisses without persisting any changes

When the user activates the Cancel toolbar button (in either Add or Edit/View mode), the system SHALL dismiss the sheet without inserting, mutating, or saving any `ExpenseItem`. Any in-flight draft state SHALL be discarded.

#### Scenario: Cancel from Add mode inserts no expense

- **WHEN** the user opens the Add sheet, types an amount and a description, and taps Cancel
- **THEN** no `ExpenseItem` is inserted into the store

#### Scenario: Cancel from Edit/View mode does not mutate the expense

- **WHEN** the user opens the Edit/View sheet for an existing `ExpenseItem`, changes the amount and description in the form, and taps Cancel
- **THEN** the `ExpenseItem` in the store retains its original values, and `lastModified` is unchanged

### Requirement: Delete Expense button is rendered only in Edit/View mode

The Add/Edit/View Expense screen SHALL render a destructive **Delete Expense** button beneath the three cards (Amount, Description, When) when, and only when, the screen is in Edit/View mode (`viewModel.isEditing == true`). In Add mode the button SHALL NOT be rendered (or rendered hidden) — there must be no Delete affordance for a draft `ExpenseItem` that has not yet been inserted.

The button SHALL be rendered with `.buttonStyle(.bordered)`, tinted red (`.tint(.red)` / destructive role), with its label expanded across the available width via `.frame(maxWidth: .infinity)`. The label text SHALL come from the localized key `addEditExpense.action.delete` with English source value `"Delete Expense"`.

The button SHALL declare a VoiceOver hint sourced from `addEditExpense.action.delete.accessibilityHint` (English source `"Permanently deletes this expense."`).

#### Scenario: Add mode does not show the Delete button

- **WHEN** the sheet is presented in Add mode (`viewModel.isEditing == false`)
- **THEN** there is no Delete Expense button anywhere on the screen, in the toolbar, or beneath the cards

#### Scenario: Edit/View mode shows the Delete button below the cards

- **WHEN** the sheet is presented in Edit/View mode for some `ExpenseItem`
- **THEN** a destructive bordered button labeled `"Delete Expense"` (key `addEditExpense.action.delete`) is rendered beneath the three cards, full-width, with `.tint(.red)` and `role: .destructive`

#### Scenario: VoiceOver announces destructive hint

- **WHEN** VoiceOver focuses the Delete Expense button in Edit/View mode
- **THEN** it announces the hint from `addEditExpense.action.delete.accessibilityHint` in addition to its destructive button trait

### Requirement: Delete Expense action requires a destructive confirmation dialog

Activating the Delete Expense button SHALL present a `confirmationDialog` with `titleVisibility: .visible`. The dialog SHALL expose exactly one explicit button: a destructive confirm button. SwiftUI's implicit Cancel button SHALL provide the cancel path; the implementation SHALL NOT add a redundant cancel button.

- The dialog title SHALL come from `addEditExpense.deleteConfirmation.title` (English source `"Delete Expense?"`).
- The dialog message body SHALL come from `addEditExpense.deleteConfirmation.message` (English source `"This action cannot be undone."`) and SHALL be rendered as a `Text` view in the `message:` trailing closure.
- The destructive confirm button label SHALL come from `addEditExpense.deleteConfirmation.confirm` (English source `"Delete Expense"`) with `role: .destructive`.

The dialog SHALL be presented from the `AddEditExpenseView` (sheet root) so it is anchored to the form, and SHALL be driven by a private `@State` flag on the view that the Delete button toggles to `true`.

#### Scenario: Tapping Delete opens the confirmation dialog without deleting

- **WHEN** the user taps the Delete Expense button in Edit/View mode
- **THEN** a confirmation dialog appears with the title from `addEditExpense.deleteConfirmation.title`, the message body from `addEditExpense.deleteConfirmation.message`, a destructive confirm button from `addEditExpense.deleteConfirmation.confirm`, and SwiftUI's implicit Cancel; no `ExpenseItem` has been deleted yet and the sheet remains on screen

#### Scenario: Cancelling the dialog leaves the expense intact

- **WHEN** the user opens the confirmation dialog and dismisses it via SwiftUI's implicit Cancel
- **THEN** the editing `ExpenseItem` is not deleted, no `ModelContext.save()` is invoked as a result of the dialog interaction, and the sheet remains in Edit/View mode with all in-flight draft state intact

#### Scenario: Confirming the dialog deletes the expense and dismisses the sheet

- **WHEN** the user taps the destructive confirm button in the dialog
- **THEN** `viewModel.delete(context:)` is invoked with the view's `@Environment(\.modelContext)`, the expense is removed from the store, and the sheet is dismissed via `dismiss()` after the VM call returns

### Requirement: Delete in Edit mode removes the row; Delete in Add mode is a no-op

The `AddEditExpenseViewModel.delete(context:)` method SHALL behave as follows:

- In **Edit/View mode**, the method SHALL invoke `context.delete(expense)` for the editing `ExpenseItem` and SHALL invoke `try? context.save()` once.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT call `context.save`, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from `delete(...)`.

`ExpenseItem` has no child relationships, so no cascade is needed; deleting the row is sufficient.

#### Scenario: Delete in Edit mode removes the expense and saves once

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Edit mode for an existing `ExpenseItem` and invokes `delete(context:)` against an in-memory `ModelContext`
- **THEN** the `ExpenseItem` is removed from the store, `context.save()` is invoked exactly once, and the in-memory `ModelContext` no longer returns the expense from a `FetchDescriptor<ExpenseItem>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Add mode and invokes `delete(context:)` against an in-memory `ModelContext` containing zero or more pre-existing `ExpenseItem` rows
- **THEN** the in-memory store contents are unchanged: no `ExpenseItem` is inserted, deleted, or mutated, and `context.save()` is not invoked as a result of the call

### Requirement: User-visible strings are registered in Localizable.xcstrings under the addEditExpense namespace

Every user-visible string introduced by `AddEditExpenseView` SHALL use `String(localized: "key", defaultValue: "...", comment: "translator context")` (or `Text(LocalizedStringKey)` where idiomatic) with a stable kebab/dot-cased key, an English source default value, and a translator `comment`. Strings SHALL be present in `simple-recurring-budgets/Resources/Localizable.xcstrings` after the build.

The screen-namespaced key prefix SHALL be `addEditExpense.*`. Keys SHALL NOT be reused from unrelated namespaces (e.g., the `addEditBudget.*` keys are budget-screen content and SHALL NOT be reused for expense-screen content even when the English copy coincidentally matches).

The minimum set of keys SHALL include:

- `addEditExpense.title.add`, `addEditExpense.title.existing` — sheet titles.
- `addEditExpense.action.cancel`, `addEditExpense.action.save` — toolbar items.
- `addEditExpense.action.delete`, `addEditExpense.action.delete.accessibilityHint` — destructive button label and VoiceOver hint.
- `addEditExpense.deleteConfirmation.title`, `addEditExpense.deleteConfirmation.message`, `addEditExpense.deleteConfirmation.confirm` — destructive confirmation dialog.
- `addEditExpense.section.amount`, `addEditExpense.section.name`, `addEditExpense.section.when` — card section labels.
- `addEditExpense.field.amount.placeholder`, `addEditExpense.field.amount.accessibilityLabel` — Amount field placeholder and VoiceOver label.
- `addEditExpense.field.name.placeholder`, `addEditExpense.field.name.accessibilityLabel` — Description field placeholder and VoiceOver label.
- `addEditExpense.field.date.label` — fallback / explicit label for the date picker.

Each key SHALL have a non-empty `comment` providing translator context.

#### Scenario: Every label has a localizable key with a comment

- **WHEN** the app is built
- **THEN** `Localizable.xcstrings` contains one entry per user-visible string introduced by the Add/Edit/View Expense screen, each with a non-empty `comment`

#### Scenario: Sheet titles use namespaced keys

- **WHEN** the sheet is opened in Add or Edit/View mode
- **THEN** the navigation title is sourced from `addEditExpense.title.add` or `addEditExpense.title.existing` respectively, not from a generic top-level English literal

#### Scenario: Expense-screen keys do not reuse addEditBudget keys

- **WHEN** an inspector reads the keys consumed by `AddEditExpenseView`
- **THEN** every key starts with `addEditExpense.`; no key is reused from the `addEditBudget.*` namespace, even when the English copy is identical

### Requirement: Screen escalates to an @Observable ViewModel per tech-design §2.1

The Add/Edit/View Expense screen SHALL use an `@Observable AddEditExpenseViewModel` owned by the view as `@State`. The VM SHALL hold draft state and pure logic only; it SHALL NOT store `ModelContext`, SHALL NOT store `AppSettings`, SHALL NOT hold `@Query` results, and SHALL NOT fetch.

The VM SHALL accept the parent `Budget` (in `init(adding:)`) or the editing `ExpenseItem` (in `init(editing:)`) and store it in a private `Mode` enum. The VM SHALL NOT retain references to `AppSettings` or `ModelContext` after `init` returns.

This pattern follows `docs/tech-design-doc.md` §2.1's VM rules, which apply because:

- Escalation criterion #1 — non-trivial draft/form state not persisted until commit — is satisfied.

The VM SHALL be testable in isolation: a test that constructs an `AddEditExpenseViewModel` and invokes `save(context:)` / `delete(context:)` against an in-memory `ModelContainer` SHALL exercise the full save/delete logic without instantiating any SwiftUI view hierarchy and without needing an `AppSettings` instance.

#### Scenario: VM does not own ModelContext

- **WHEN** `AddEditExpenseViewModel` is inspected
- **THEN** it has no stored property of type `ModelContext` and no `init(context:)` taking a `ModelContext`; its `save(...)` and `delete(...)` methods receive the context as a parameter at the call site

#### Scenario: VM does not retain AppSettings

- **WHEN** `AddEditExpenseViewModel` is inspected
- **THEN** it has no stored property of type `AppSettings`; the Amount card's currency-prefix display reads `AppSettings` view-side via `@Environment(AppSettings.self)`

#### Scenario: VM is testable in isolation

- **WHEN** a test constructs an `AddEditExpenseViewModel` and invokes `save(context:)` or `delete(context:)` against an in-memory `ModelContainer`
- **THEN** the test exercises the full save/delete logic without instantiating any SwiftUI view hierarchy and without needing an `AppSettings` instance for the call
