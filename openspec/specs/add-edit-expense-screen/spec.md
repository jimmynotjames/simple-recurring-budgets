# add-edit-expense-screen Specification

Updated from change `pause-resume-budget` (2026-05-16). Updated from change `finish-recently-used-expenses` (2026-05-28).

## Purpose

SwiftUI view for adding a new `ExpenseItem` or viewing and editing an existing one on a single surface (F-2.04). Card-based form (Amount, Description, When) backed by `AddEditExpenseViewModel`. Presented as a sheet (Add mode via `SheetRoute.addExpense`) or pushed (Edit mode via `AppRoute.expenseDetail`). Navigation context provided by the caller, not by `AddEditExpenseView` itself.
## Requirements
### Requirement: Add/Edit/View Expense screen is a single view for both create and edit modes

The system SHALL present a single SwiftUI view, `AddEditExpenseView`, used for both creating a new `ExpenseItem` (Add mode) and editing an existing `ExpenseItem` (Edit/View mode). Per F-2.04, the screen does NOT distinguish between Edit and View — Edit mode IS the View mode and there is no read-only toggle.

`AddEditExpenseView` SHALL NOT wrap its own body in a `NavigationStack`. The navigation context (and therefore the navigation bar that hosts toolbar items) SHALL be provided by the caller:

- When presented as a **sheet** (`SheetRoute.addExpense(Budget)`), `RootView` SHALL wrap `AddEditExpenseView` in a `NavigationStack` at the sheet presentation site.
- When presented as a **push** (`AppRoute.expenseDetail(ExpenseItem)`), `RootView`'s existing outer `NavigationStack` provides the navigation context; no additional wrapper is needed.

This ensures that the view is not embedded inside a nested `NavigationStack`, which would produce a double navigation bar when pushed.

The `AddEditExpenseView` previews SHALL also wrap the view in a `NavigationStack` so that toolbar items render correctly.

The two access paths are:

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

#### Scenario: Edit-mode title flips between Expense and Add Funds

- **WHEN** the screen is pushed in Edit mode for an `ExpenseItem` with `isAddFunds == false`
- **THEN** the navigation title is sourced from `addEditExpense.title.existing` ("Expense")

- **WHEN** the screen is pushed in Edit mode for an `ExpenseItem` with `isAddFunds == true`
- **THEN** the navigation title is sourced from `addEditExpense.title.existing.addFunds` ("Add Funds")

- **WHEN** the user flips the toggle to the opposite state
- **THEN** the navigation title reactively updates to the matching key from the table above

### Requirement: Add/Edit/View Expense screen toolbar items differ by mode

The Add/Edit/View Expense screen SHALL expose toolbar items according to the active mode:

- **Add mode** (`viewModel.isEditing == false`): a leading Cancel button (key `addEditExpense.action.cancel`, placement `.cancellationAction`) that dismisses without persisting any changes, and a trailing Save button (key `addEditExpense.action.save`, placement `.confirmationAction`) whose enablement follows the "Save is enabled only when amount is strictly positive" requirement.
- **Edit/View mode** (`viewModel.isEditing == true`): a trailing Save button only. The Cancel button SHALL NOT be rendered. The system-provided back button in the `NavigationStack` serves as the discard path — navigating back without tapping Save discards any in-flight field changes.

The Save button SHALL render with `.fontWeight(.semibold)` in both modes. The Cancel button locale key `addEditExpense.action.cancel` remains in the String Catalog (it is used in Add mode); it is simply not rendered in Edit mode.

No other toolbar items SHALL be present on this screen in either mode.

#### Scenario: Add mode shows Cancel and Save toolbar items

- **WHEN** the sheet is visible in Add mode (`viewModel.isEditing == false`)
- **THEN** the navigation bar SHALL show a leading Cancel button (key `addEditExpense.action.cancel`) and a trailing Save button (key `addEditExpense.action.save`)

#### Scenario: Edit mode shows Save only — no Cancel button

- **WHEN** the screen is pushed in Edit/View mode (`viewModel.isEditing == true`)
- **THEN** the navigation bar SHALL show only the trailing Save button; the leading Cancel button SHALL NOT be present

#### Scenario: Back chevron is the discard path in Edit mode

- **WHEN** the screen is in Edit/View mode and the user navigates back without tapping Save
- **THEN** no changes are persisted; `dismiss()` is NOT called explicitly from a Cancel button; the `NavigationStack` back action pops the view

#### Scenario: Save remains enabled by positive amount in both modes

- **WHEN** `viewModel.amount > 0` in either Add or Edit/View mode
- **THEN** the Save button is enabled regardless of whether Cancel is visible

#### Scenario: Cancel in Add mode dismisses without saving

- **WHEN** the sheet is in Add mode and the user taps Cancel
- **THEN** the sheet is dismissed and no `ExpenseItem` is inserted

### Requirement: Form fields are Amount, Description (optional), and When (date/time)

The Add/Edit/View Expense screen SHALL collect exactly three user-editable fields, organised into three cards (Amount, Description, When) per the user-approved layout. Fields SHALL always be directly editable in place — there SHALL NOT be any "edit mode" toggle that switches between read-only and editable states (per F-2.04 AC).

The fields are:

- **Amount** (`Decimal?` in `AddEditExpenseViewModel`) — entered via a **`DecimalInputField`** — a `UITextField`-backed `UIViewRepresentable` — rather than SwiftUI's `TextField(value:format:)` (which rejects keystrokes whenever parsing throws, breaking RTL / non-Western-digit entry) or `TextField(text:)` + `.onChange` (which on iOS 17+ fails to render typed text until the field resigns first responder). The field is **seeded** from the draft `Decimal?` via `OptionalDecimalFormatStyle.editableText(_:)` at the expense currency's minor-unit precision (e.g. 0 for JPY, 2 for USD, 3 for BHD/KWD; no grouping separators), and an empty field maps to `nil` (blank default in Add mode). Each edit is parsed back to `Decimal?` via the style's **locale-aware `parseStrategy`**, which accepts whatever numbering system the locale's keyboard emits (Western, Arabic-Indic, Devanagari, …). Entry is **capped live** to the currency's minor-unit count by the field's delegate: 0-decimal currencies (JPY, KRW, …) reject the decimal separator entirely (no fractional entry), and other currencies accept at most that many fraction digits. Placeholder `"0"` (key `addEditExpense.field.amount.placeholder`). Keyboard type SHALL be `.decimalPad`. A currency symbol/code SHALL be displayed adjacent to the field in the same `HStack`, on the **locale-correct side** (leading or trailing); the decoration is derived from `settings.currencyDisplay.affixes(for: viewModel.currencyCode)` — which returns `(leading, trailing)` strings whose placement and spacing follow the same currency `FormatStyle` used by `Decimal.formatted(currencyCode:display:locale:)` (e.g. leading `"$"` for USD in en_US, trailing `" €"` for EUR in fr_FR), mirroring correctly in RTL — and SHALL update reactively whenever `settings.currencyDisplay` changes. The decoration `Text`(s) SHALL be `accessibilityHidden`. Accessibility label `"Expense amount"` (key `addEditExpense.field.amount.accessibilityLabel`). The view SHALL read `AppSettings` via `@Environment(AppSettings.self)`; the VM SHALL NOT store `AppSettings`.
- **Description** (`String` in the VM, persisted as `String?`) — bound to a single-line `TextField` in the Description card. Placeholder `"e.g. Coffee"` (key `addEditExpense.field.name.placeholder`). Section label `"Description (optional)"` (key `addEditExpense.section.name`). Accessibility label `"Expense description"` (key `addEditExpense.field.name.accessibilityLabel`). Per F-2.04 AC, the description is optional — Save SHALL NOT be gated on it being non-empty.
- **When** (`Date`) — bound to a `DatePicker` with `displayedComponents: [.date, .hourAndMinute]` and `.datePickerStyle(.compact)`. Section label `"When"` (key `addEditExpense.section.when`). The picker's own label is hidden (`.labelsHidden()`) and provided via the section header.

Section labels for the three cards use keys `addEditExpense.section.amount`, `addEditExpense.section.name`, and `addEditExpense.section.when`.

The currency code shown in the Amount decoration SHALL be derived as follows:

- In Add mode, from the in-flight `Budget.currencyCode`.
- In Edit/View mode, from `expense.budget?.currencyCode`, falling back to `Locale.current.currency?.identifier ?? "USD"` if the parent budget reference is `nil` (defensive against orphan rows synced from another device).

The currency code SHALL be stored on the VM as a `let` (immutable for the lifetime of the sheet); the user CANNOT change the per-expense currency from this screen.

#### Scenario: All three fields render in their cards

- **WHEN** the sheet is visible in either Add or Edit/View mode
- **THEN** the screen displays three cards in this order: Amount, Description, When; the Amount card contains the currency decoration and the numeric field; the Description card contains the single-line text field; the When card contains the compact date/time picker

#### Scenario: Amount currency decoration matches AppSettings.currencyDisplay on the locale-correct side

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"USD"`, and the locale is `en_US`
- **THEN** the Amount card displays `"$"` as a **leading** decoration before the numeric field, and no trailing decoration

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"EUR"`, and the locale is `fr_FR`
- **THEN** the Amount card displays the `"€"` symbol as a **trailing** decoration after the numeric field, and no leading decoration

- **WHEN** `settings.currencyDisplay == .code` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD"` as a leading decoration

- **WHEN** `settings.currencyDisplay == .codeAndSymbol` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD $"` as a leading decoration

#### Scenario: Currency decoration updates live when settings change

- **WHEN** the user changes `AppSettings.currencyDisplay` while the sheet is open
- **THEN** the decoration around the Amount field updates immediately to reflect the new preference without dismissing or reloading the sheet

#### Scenario: Amount fraction precision follows the budget currency

- **WHEN** the budget's currency is a 3-decimal currency (e.g. `"BHD"`) and an existing amount of `1.234` is shown
- **THEN** the field displays all three fraction digits (`1.234`), not a value truncated to two places

- **WHEN** the budget's currency is a 0-decimal currency (e.g. `"JPY"`)
- **THEN** the field renders the amount with no fraction digits, AND tapping the decimal-separator key during entry has no effect (fractional input is not possible)

#### Scenario: Amount field parses optional Decimal with locale-aware parsing

- **WHEN** the user clears the Amount `TextField` or leaves it empty in Add mode
- **THEN** the draft `amount` is `nil` (blank), not `0`

- **WHEN** the user enters a number in the Amount `TextField`
- **THEN** the parse strategy reads the text using a locale-aware `Decimal.FormatStyle`, so locale-appropriate decimal/grouping separators apply; successful parse yields `Decimal`; the underlying VM state remains `Decimal?` (entered value or `nil` when empty)

- **WHEN** the user enters an unparseable string (e.g. via paste)
- **THEN** the parse strategy throws a `CocoaError` and the field rejects the input

#### Scenario: Amount field accepts non-Western numerals

- **WHEN** the locale's `.decimalPad` emits non-Western digits (e.g. Arabic-Indic `٠١٢٣…` in `ar_EG`/`ar_SA`, Extended Arabic-Indic in `fa_IR`, or Devanagari in `ne_NP`) and the user taps digits into the Amount field
- **THEN** the digits SHALL be accepted and parsed to the corresponding `Decimal` (the field SHALL NOT reject the keystrokes), because parsing routes through the locale-aware `Decimal.FormatStyle` rather than `Decimal(string:locale:)`

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
- `currencyCode = budget.currencyCode` (matches the parent budget's currency for the prefix display).
- `date` — seeded per the bound budget's `BudgetSnapshot.lifecycleState` at sheet-open time:
  - `.paused` (with a recoverable pause moment) → the most recent unbalanced `.pause` event's `effectiveDate` (guaranteed to lie inside the active union; matches the upper bound of `dateRange`).
  - `.postEnd` (with `budget.endDate` non-`nil`) → the last moment of `endDate`'s day (specifically `calendar.startOfDay(for: Date.addingTimeInterval(86400, to: startOfDay(endDate))) - 1` — i.e. the same upper-bound expression used by `dateRange` for post-end / specific-dates budgets). This guarantees the picker opens inside its allowed range; without this clamp the default would be `Date()` (now), which sits above the upper bound when `now > endDate`.
  - All other states (`.active`, `.preStart`, `.paused` without a recoverable pause moment) → `max(Date(), budget.effectiveStartDate)` (the existing rule — floor at the budget's start so a pre-start picker opens at the start date).

The defaults SHALL NOT update reactively in response to changes in `AppSettings` or the parent `Budget` after the sheet opens; the user can edit any field manually before saving.

The `cachedStartDateFormatted` and `cachedEndDateFormatted` `String?` properties on the VM SHALL be populated only when the bound budget is `.preStart` (start) or `.postEnd` (end) at sheet-open time; they SHALL be `nil` otherwise. They are consumed by the `dateContextCaption` requirement.

#### Scenario: Add mode opens with documented defaults for an active budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `currencyCode == "USD"` whose lifecycle is `.active`
- **THEN** the form shows: amount field blank (draft `nil`), description field empty (placeholder visible), When picker at the current date and time, currency prefix derived from `"USD"` and the user's `currencyDisplay` preference; Save is disabled because `amount` is `nil`

#### Scenario: Add mode seeds date to pause moment for paused budget

- **WHEN** the sheet opens in Add mode for a paused budget with the most-recent unbalanced `.pause` event at `2026-05-10 14:00`
- **THEN** the seeded `date` equals `2026-05-10 14:00`

#### Scenario: Add mode seeds date to endDate end-of-day for post-end budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `endDate == 2026-04-15` whose lifecycle is `.postEnd`
- **THEN** the seeded `date` equals the last moment of `2026-04-15` (i.e. `2026-04-15 23:59:59`), guaranteeing the picker opens inside `dateRange`'s `[effectiveStartDate, endDate-end-of-day]` window

#### Scenario: Add mode seeds date to effectiveStartDate for pre-start budget

- **WHEN** the sheet opens in Add mode for a `Budget` with `startDate == 2026-06-01` whose lifecycle is `.preStart` (`now < startDate`)
- **THEN** the seeded `date` equals `2026-06-01 00:00` (i.e. `max(Date(), budget.effectiveStartDate)`, which collapses to `effectiveStartDate` when `Date()` is earlier)

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

The `AddEditExpenseViewModel` SHALL expose a `save` method and a `delete` method that take `ModelContext` at the call site and surface a persistence-save failure to the caller (e.g. marked `throws`). Each method SHALL route its `context.save()` through the shared persistence-save helper rather than `try? context.save()`. The view SHALL read `@Environment(\.modelContext)`, invoke `save`/`delete` from inside `body`, and dismiss the sheet **only** when the call returns without error; on a thrown persistence error the view SHALL present the standard save-error alert and SHALL NOT dismiss (see the `persistence-error-handling` capability). The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The save and delete bodies SHALL NOT consult `AppSettings`. The VM SHALL NOT have any stored property of type `ModelContext` and SHALL NOT have any stored property of type `AppSettings`.

#### Scenario: Save reports failure to the caller

- **WHEN** `AddEditExpenseViewModel.save` is inspected
- **THEN** it takes `ModelContext` at the call site, does not take `AppSettings`, surfaces persistence-save failure to its caller (e.g. is marked `throws`), and routes its save through the shared persistence-save helper

#### Scenario: Delete reports failure to the caller

- **WHEN** `AddEditExpenseViewModel.delete` is inspected
- **THEN** it takes `ModelContext` at the call site, does not take `AppSettings`, surfaces persistence-save failure to its caller (e.g. is marked `throws`), and routes its save through the shared persistence-save helper

#### Scenario: VM does not own ModelContext or AppSettings

- **WHEN** `AddEditExpenseViewModel` is inspected
- **THEN** it has no stored property of type `ModelContext`, no stored property of type `AppSettings`, and no `init` taking either type

#### Scenario: View dismisses only on a successful save or delete

- **WHEN** the user activates Save or Delete and the method returns without error
- **THEN** the sheet dismisses; **AND WHEN** the method throws a persistence error, the sheet stays open and the save-error alert is shown

### Requirement: Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget

When the user activates Save in Add mode, the system SHALL:

0. **Guard:** If validation would disable Save (`!canSave`), the implementation SHALL return without inserting an `ExpenseItem` (defence in depth if save is invoked without a valid draft).
1. Compute `trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)`. If `trimmedName.isEmpty == true`, the persisted name SHALL be `nil`; otherwise the persisted name SHALL be the trimmed value.
2. Compute `signedAmount = isAddFunds ? -amount! : amount!`. The unwrap is safe because `canSave` guarantees `amount != nil && amount > 0`.
3. Construct an `ExpenseItem(amount: signedAmount, name: trimmedName, date: date)`. The resulting `ExpenseItem.isAddFunds` SHALL equal the viewmodel's `isAddFunds`.
4. Set `expense.budget = budget` (the in-flight `Budget` from the VM's `Mode.add` associated value), establishing the parent relationship before insert.
5. Call `context.insert(expense)`.
6. Persist via the shared persistence-save helper (operation `expense_create`), which throws on failure; the method propagates that error to the caller instead of swallowing it with `try?`.
7. On success, the view dismisses the sheet. On a thrown persistence error, the view presents the save-error alert and does not dismiss; the inserted-but-unsaved `ExpenseItem` remains in the context so Retry re-attempts the same save.

The new expense SHALL appear in the budget's expense list immediately due to SwiftData's reactivity once the save succeeds. CloudKit sync SHALL propagate the new row through the existing pipeline; no schema or container changes are introduced.

The `AnalyticsProperty.isAddFunds` property on the `expense_logged` event SHALL reflect the just-inserted `ExpenseItem.isAddFunds` (which equals the viewmodel's `isAddFunds` at Save time). The `expense_logged` event SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: Add Save inserts a positive-amount expense when Add Funds is off

- **WHEN** the user activates Save in Add mode with `amount = 5.00`, `name = "Coffee"`, `date = 2026-04-29 10:00`, `isAddFunds = false`, against an in-memory `ModelContainer` containing the in-flight `Budget`, and the save succeeds
- **THEN** the store contains exactly one new `ExpenseItem` with `amount == 5.00` (positive), `name == "Coffee"`, `date == 2026-04-29 10:00`, `budget` referencing the in-flight `Budget`, and `isAddFunds == false`

#### Scenario: Add Save inserts a negative-amount expense when Add Funds is on

- **WHEN** the user activates Save in Add mode with `amount = 25.00`, `name = "Add funds"`, `date = 2026-04-29 10:00`, `isAddFunds = true`, and the save succeeds
- **THEN** the inserted `ExpenseItem.amount == -25.00` (sign flipped), `isAddFunds == true`, `name == "Add funds"`

#### Scenario: Add Save trims description whitespace

- **WHEN** the user activates Save in Add mode with `name = "  Coffee  "` and the save succeeds
- **THEN** the inserted `ExpenseItem.name` is `"Coffee"` (whitespace trimmed)

#### Scenario: Add Save persists nil description for whitespace-only input

- **WHEN** the user activates Save in Add mode with `name = "   "` (whitespace only) or `name = ""` and the save succeeds
- **THEN** the inserted `ExpenseItem.name` is `nil`

#### Scenario: Add Save guards against !canSave

- **WHEN** save is invoked while `canSave == false`
- **THEN** no `ExpenseItem` is inserted and no save is attempted

#### Scenario: Add Save emits expense_logged with correct isAddFunds

- **WHEN** the user activates Save in Add mode with `isAddFunds = true`, `amount = 25.00`, and the save succeeds
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: true`

- **WHEN** the user activates Save in Add mode with `isAddFunds = false`, `amount = 5.00`, and the save succeeds
- **THEN** the `expense_logged` analytics event is fired with `AnalyticsProperty.isAddFunds: false`

#### Scenario: Failed Add-mode save keeps the sheet open and does not fire expense_logged

- **WHEN** the user activates Save in Add mode and the persistence-save helper throws
- **THEN** the sheet remains open with the drafted values intact, the save-error alert is presented, and the `expense_logged` event is not fired

### Requirement: Save in Edit mode mutates only changed fields and bumps lastModified once

When the user activates Save in Edit/View mode, the system SHALL compare each editable field on the existing `ExpenseItem` to its corresponding draft value. For each field whose stored value differs from the draft value, the system SHALL write the draft value back to the `ExpenseItem`. The system SHALL set `ExpenseItem.lastModified = Date()` exactly once if at least one field changed. If no field changed, the system SHALL NOT mutate `lastModified` and SHALL NOT attempt a save. After mutating any field, the system SHALL persist via the shared persistence-save helper (operation `expense_edit`), which throws on failure. The view SHALL dismiss the sheet only when the save returns without error; on a thrown persistence error it SHALL present the save-error alert and SHALL NOT dismiss, leaving the mutated-but-unsaved `ExpenseItem` so a Retry re-attempts the same save.

The fields compared are:

- **Amount**: compared as `expense.displayAmount != newAmount` (where `newAmount` is the unwrapped draft `amount`).
- **Description**: compared as `expense.name != trimmedName`.
- **Date**: compared via `Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute)`. Sub-minute differences SHALL NOT count as a change.

The system SHALL NOT touch any other persisted field of `ExpenseItem` (notably `expenseType`, `createdAt`, `id`, the `budget` relationship). The `expense_edited` event SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: No-op Save does not bump lastModified

- **WHEN** the user opens the sheet for an existing `ExpenseItem`, makes no changes, and taps Save
- **THEN** the `ExpenseItem.lastModified` is unchanged and no save is invoked

#### Scenario: Single-field change updates lastModified once

- **WHEN** the user changes only the description on an existing `ExpenseItem` and taps Save and the save succeeds
- **THEN** the `ExpenseItem.name` is updated, `lastModified` is set to a `Date()` greater than its prior value, and no other persisted field is mutated

#### Scenario: Multi-field change is batched into a single save

- **WHEN** the user changes both the description and the amount on an existing `ExpenseItem` and taps Save and the save succeeds
- **THEN** both fields are written, `lastModified` is set to a single `Date()` value, and the save helper is called exactly once for the whole edit

#### Scenario: Sub-minute date change is treated as no-op

- **WHEN** the user opens the sheet, the picker emits a sub-minute drift on the Date, and the user taps Save without any other change
- **THEN** the `ExpenseItem.lastModified` is unchanged and no save is invoked

#### Scenario: Failed Edit-mode save keeps the sheet open

- **WHEN** the user changes a field, taps Save, and the persistence-save helper throws
- **THEN** the sheet remains open with the edits intact, the save-error alert is presented, and `expense_edited` is not fired

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

### Requirement: Cancel dismisses without persisting any changes

When the user activates the Cancel toolbar button (available in Add mode only), the system SHALL dismiss the sheet without inserting, mutating, or saving any `ExpenseItem`. Any in-flight draft state SHALL be discarded. In Edit/View mode the Cancel button is not rendered; the system back button provides the equivalent discard path.

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

The `AddEditExpenseViewModel` delete method SHALL behave as follows:

- In **Edit/View mode**, the method SHALL invoke `context.delete(expense)` for the editing `ExpenseItem` and SHALL persist via the shared persistence-save helper (operation `expense_delete`) once. The method SHALL surface a persistence-save failure to its caller rather than swallowing it with `try?`.
- In **Add mode**, the method SHALL be a no-op: it SHALL NOT call `context.delete`, SHALL NOT save, and SHALL NOT mutate any state.

The VM SHALL NOT store `ModelContext`; the context SHALL be passed at the call site every invocation. The VM SHALL NOT consult `AppSettings` from delete. `ExpenseItem` has no child relationships, so no cascade is needed. The view SHALL dismiss only on a successful delete; on failure it SHALL present the save-error alert and SHALL NOT dismiss.

#### Scenario: Delete in Edit mode removes the expense and saves once

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Edit mode for an existing `ExpenseItem` and invokes the delete method against an in-memory `ModelContext`, and the save succeeds
- **THEN** the `ExpenseItem` is removed from the store, the save helper is invoked exactly once, and the in-memory `ModelContext` no longer returns the expense from a `FetchDescriptor<ExpenseItem>` query

#### Scenario: Delete is a no-op in Add mode

- **WHEN** a test constructs an `AddEditExpenseViewModel` in Add mode and invokes the delete method against an in-memory `ModelContext` containing zero or more pre-existing `ExpenseItem` rows
- **THEN** the in-memory store contents are unchanged: no `ExpenseItem` is inserted, deleted, or mutated, and no save is invoked as a result of the call

#### Scenario: Failed Edit-mode delete keeps the sheet open

- **WHEN** the user confirms Delete Expense and the persistence-save helper throws
- **THEN** the sheet remains open and the save-error alert is presented

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

All keys (including the Add Funds keys introduced by F-6.01) SHALL be present in `Localizable.xcstrings` with translations for all 38 App Store storefront locales per `docs/main-prd.md` §6.8 and F-3.03; the `scripts/translate_catalog/` pipeline SHALL be run as part of any change that adds or modifies keys.

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

### Requirement: Date picker bounds restrict the When field to the budget's active periods when paused

When the bound budget's current `BudgetLifecycleResult.lifecycleState == .paused`, the When (date / time) `DatePicker` SHALL constrain its accepted values to the union of the budget's active periods, computed from the budget's `LifecycleEvent` history.

The constraint SHALL be implemented in two stages:

1. **Picker range.** The `DatePicker` `in:` parameter SHALL be the closed range `[firstActivePeriodStart, pauseEffectiveDate]`, where:
   - `firstActivePeriodStart` is the `effectivePeriodStart` of the budget's earliest active period since `Budget.startDate` (falling back to `Budget.createdAt` if `startDate` is `nil`).
   - `pauseEffectiveDate` is the `effectiveDate` of the most recent `.pause` `LifecycleEvent` that is not followed by a later `.resume`. This is the precise upper bound — it explicitly permits **same-period-before-pause-moment** entries (e.g., the user paused at 11:00 today and can still log a coffee dated 09:00 today, because 09:00 lies inside the pause-action period and before the pause moment). It also implicitly inherits the math classifier's "pause-action period is active for math" rule.
   - When `Budget.endDate` is set, the upper bound SHALL additionally be clamped to `min(pauseEffectiveDate, endDate)`.
2. **Save-time validation.** When the user attempts to Save, the screen SHALL validate that the selected date lies inside one of the active-period intervals (not merely inside the bounding range above). If the selected date falls inside a paused gap (e.g., between two active intervals after multiple pause/resume cycles) or outside `[Budget.startDate, Budget.endDate]`, Save SHALL be blocked and the inline `.caption`/`.secondary` slot below the When card SHALL show the localized message `addEditExpense.date.outOfRange.caption` (en-US "Pick a date within an active period of this budget."), replacing the proactive paused note (see "Add Expense surfaces a proactive paused note while budget is paused"). Save SHALL become enabled again as soon as the user picks a date inside an active interval.

When `BudgetLifecycleResult.lifecycleState != .paused`, the date-bounds rule SHALL be the existing rule (no paused-state constraints introduced by this requirement). The pre-start (`now < startDate`) and post-end (`now > endDate`) clamping rules from F-2.04 apply independently and are not changed by this requirement.

The same two-stage validation SHALL apply in Add mode (the in-flight budget passed via `SheetRoute.addExpense(budget)`) and in Edit mode (`expense.budget`). In Edit mode, if the existing `expense.date` is outside the valid union (e.g., the user edits an expense from a since-paused budget whose date now sits inside a paused gap created by a later pause action), the picker SHALL load with its current value but Save SHALL be blocked with the same caption until the user picks a date inside an active interval, or until the user reverts the date to a value inside the active union.

The date seed for Add mode on a paused budget SHALL be `pauseEffectiveDate` (the most recent unbalanced `.pause` event's `effectiveDate`), guaranteeing that the initial value lies inside the active union and the picker does not open with an out-of-range default.

#### Scenario: Paused budget Add Expense restricts picker to active range with pause moment as upper bound

- **WHEN** the user opens Add Expense for a daily budget whose `startDate = 2026-04-01`, currently paused since `2026-05-10 14:00`
- **THEN** the When `DatePicker` accepts dates only in `[2026-04-01 00:00, 2026-05-10 14:00]`

#### Scenario: Same-period-before-pause-moment entry is allowed

- **WHEN** the user pauses a daily budget at 2026-05-10 11:00 and then opens Add Expense for that budget at 2026-05-10 11:05
- **THEN** the When `DatePicker` accepts a date of 2026-05-10 09:00 (same period, before the pause moment); Save is enabled when the user picks that date with a positive amount

#### Scenario: Active budget Add Expense uses the original date-bounds rule

- **WHEN** the user opens Add Expense for an active budget
- **THEN** the When `DatePicker` is NOT additionally constrained by this requirement; only the existing F-2.04 pre-start / post-end / `[startDate, endDate]` rules apply

#### Scenario: Save is blocked when the picked date sits inside a paused gap

- **WHEN** a budget has lifecycle history `[(.pause, 2026-04-10), (.resume, 2026-04-20), (.pause, 2026-05-01)]` and the user selects a date of 2026-04-15 in Add mode
- **THEN** Save is disabled, the inline caption `addEditExpense.date.outOfRange.caption` is shown directly below the When card (replacing the proactive paused note in the same slot), and the caption disappears (the proactive note returns and Save re-enables) as soon as the user picks a date inside one of the active intervals

#### Scenario: Edit mode loads an out-of-range existing date but blocks Save

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose `date` now sits inside a paused gap (created by a pause action after the expense was logged)
- **THEN** the When picker loads with the stored date, Save is disabled, and the inline caption `addEditExpense.date.outOfRange.caption` is shown until the user picks a date inside an active interval

#### Scenario: Save succeeds when picked date is inside the active union

- **WHEN** the user picks a date inside an active interval in either Add or Edit mode
- **THEN** Save is enabled, no inline out-of-range caption is shown, and on activation the screen persists the `ExpenseItem` per the existing Save requirements

### Requirement: Add Expense surfaces a proactive paused note while budget is paused

The Add/Edit Expense screen SHALL render at most one inline caption (`.font(.caption)` / `.foregroundStyle(.secondary)`) directly below the When card, resolved at body-evaluation time from the bound budget's lifecycle state via a single VM property `dateContextCaption: String?`. The view SHALL NOT render any caption when this property returns `nil`.

The caption is resolved in priority order. The screen SHALL never render two captions stacked.

1. **Paused + date out of range.** When `cachedBudgetSnapshot?.lifecycleState == .paused` AND the picked `date` falls outside the active union (per the "Date picker bounds restrict the When field to the budget's active periods when paused" requirement), the caption SHALL be the localized string keyed `addEditExpense.date.outOfRange.caption` (en-US: *"Pick a date within an active period of this budget."*).
2. **Paused + date valid.** When `cachedBudgetSnapshot?.lifecycleState == .paused` AND the picked `date` lies inside the active union AND a `pauseEffectiveDate` is recoverable, the caption SHALL be the localized key `addEditExpense.paused.caption.format` (en-US: *"Paused since %@. You can still add expenses dated before then."*) with the formatted `pauseEffectiveDate` (locale-aware `Date.formatted(date: .abbreviated, time: .omitted)`). This is the proactive paused note.
3. **Add mode + pre-start.** When the VM is in Add mode (`isEditing == false`) AND `cachedBudgetSnapshot?.lifecycleState == .preStart` AND `cachedStartDateFormatted` is non-`nil`, the caption SHALL be the localized key `addEditExpense.preStart.caption.format` (en-US: *"Budget starts on %@."*) with `cachedStartDateFormatted`. (Per F-2.04.)
4. **Add mode + post-end.** When the VM is in Add mode AND `cachedBudgetSnapshot?.lifecycleState == .postEnd` AND `cachedEndDateFormatted` is non-`nil`, the caption SHALL be the localized key `addEditExpense.postEnd.caption.format` (en-US: *"Budget ended on %@."*) with `cachedEndDateFormatted`. (Per F-2.04.)
5. **Otherwise** the property SHALL return `nil` (active budget in Add mode, any state in Edit mode that doesn't match the paused branches, etc.).

Edit-mode pre-start / post-end captions are intentionally suppressed (Add-mode-only per F-2.04): an existing `ExpenseItem` already carries its stored date, so the clamped-default rationale doesn't apply.

The paused branches (priority 1 and 2) apply in BOTH Add mode and Edit mode — these are about explaining the date-bounds constraint, which still applies in Edit mode when the bound budget is paused.

The pre-start and post-end captions SHALL persist for the entire lifetime of the sheet while the budget is in that lifecycle state — they are NOT gated on whether the picker still shows the clamped default — since the underlying `[startDate, endDate]` constraint still applies after the user edits the field.

#### Scenario: Paused-budget Add Expense shows the proactive note at sheet open

- **WHEN** the user opens Add Expense for a daily budget whose `lifecycleState == .paused` with `pauseEffectiveDate == 2026-05-10`
- **THEN** the `.caption`/`.secondary` line below the When card reads "Paused since May 10, 2026. You can still add expenses dated before then." and is visible from sheet appearance

#### Scenario: Proactive note persists across date edits within the valid range

- **WHEN** the user opens Add Expense for a paused budget, then changes the date to an earlier valid date inside an active interval
- **THEN** the proactive paused note continues to render in the same slot; no violation caption appears

#### Scenario: Violation caption replaces the proactive note in the same slot

- **WHEN** the user picks a date inside a paused gap (e.g., between two pause/resume cycles)
- **THEN** the proactive note is no longer rendered; instead the slot shows `addEditExpense.date.outOfRange.caption` ("Pick a date within an active period of this budget."), and Save is disabled. As soon as the user picks a date inside an active interval, the slot reverts to the proactive note and Save re-enables.

#### Scenario: Active-budget Add Expense shows no caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .active`
- **THEN** `dateContextCaption` returns `nil` and no caption is rendered

#### Scenario: Edit mode on paused budget shows the proactive note

- **WHEN** the user opens an existing `ExpenseItem` in Edit mode whose budget is currently paused, and the expense's `date` is inside a prior active period
- **THEN** the proactive paused note is rendered with the budget's `pauseEffectiveDate`; Save is enabled (because the existing date is valid)

#### Scenario: Add mode on pre-start budget shows the pre-start caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .preStart` with `startDate == 2026-06-01`
- **THEN** the caption below the When card reads "Budget starts on Jun 1, 2026." (key `addEditExpense.preStart.caption.format`) for the lifetime of the sheet, irrespective of whether the user changes the picked date

#### Scenario: Add mode on post-end budget shows the post-end caption

- **WHEN** the user opens Add Expense for a budget whose `lifecycleState == .postEnd` with `endDate == 2026-04-15`
- **THEN** the caption below the When card reads "Budget ended on Apr 15, 2026." (key `addEditExpense.postEnd.caption.format`) for the lifetime of the sheet

#### Scenario: Edit mode on pre-start budget shows no pre-start caption

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose budget is `.preStart`
- **THEN** the pre-start caption is NOT rendered (Add-mode-only per F-2.04); the existing expense's stored date already accommodates the bounds

#### Scenario: Edit mode on post-end budget shows no post-end caption

- **WHEN** the user opens Edit Expense for an existing `ExpenseItem` whose budget is `.postEnd`
- **THEN** the post-end caption is NOT rendered (Add-mode-only per F-2.04)

#### Scenario: Paused state outranks pre-start / post-end in caption priority

- **WHEN** a hypothetical lifecycle classification reported `.paused` simultaneously with `.preStart` (which the moment-granular UI classifier prevents in practice)
- **THEN** the paused caption (priority 1 or 2) is rendered, not the pre-start or post-end caption — the priority ordering is defensive against future overlapping-state changes

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

### Requirement: AddEditExpenseView includes an Add Funds toggle card at the end of the form

The Add/Edit/View Expense screen SHALL render a fourth card — the **Add Funds card** — immediately after the When card and before the Delete button (the Delete button only appears in Edit mode). The card SHALL contain:

- A `Toggle` whose label is the localized key `addEditExpense.addFunds.toggle.label` (en-US `"Add funds"`).
- An explanatory caption immediately below the Toggle row, in `.caption` font with `.secondary` foreground, using the localized key `addEditExpense.addFunds.toggle.caption` (en-US `"Adds to your remaining balance instead of subtracting."`).

The Toggle's tint SHALL be `.accentColor` (matching the carry-over toggle pattern in `AddEditBudgetView.swift:245` and the analytics toggle in `SettingsView.swift:144`). The Toggle SHALL be bound to `AddEditExpenseViewModel.isAddFunds: Bool` (default `false` in Add mode; seeded from the existing row in Edit mode per the "Edit/View mode seeds form fields from the existing ExpenseItem" requirement).

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

When `AddEditExpenseViewModel.isAddFunds == true`, the Amount card's currency decoration `Text`(s) and the numeric `TextField` SHALL render with `.foregroundStyle(Color.moneySurplus)` (matching the green tint used by add-funds rows on the Budget detail screen). When `isAddFunds == false`, the decoration uses `.secondary` and the numeric field uses `.primary` (the existing styling). The tint SHALL apply to whichever side(s) the locale-correct currency decoration occupies (leading and/or trailing). The transition is driven reactively by the `@Observable` viewmodel and applies without explicit animation.

#### Scenario: Amount text tints green when Add Funds is on

- **WHEN** the user toggles Add Funds on
- **THEN** the currency decoration and the numeric field text render in `Color.moneySurplus`

#### Scenario: Amount text reverts to default colors when Add Funds is off

- **WHEN** the user toggles Add Funds off (from on)
- **THEN** the currency decoration renders in `.secondary` and the numeric field text renders in `.primary`

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

### Requirement: Add Expense surfaces a Recents section above the Amount card (F-7.04)

In Add mode, the Add/Edit Expense screen SHALL render a "Recents" section above the Amount card when the bound budget has at least one prior expense item eligible to surface as a suggestion. In Edit mode, the section SHALL NOT render. When the bound budget has zero eligible candidates, the section SHALL NOT render at sheet-open and SHALL NOT later appear during the sheet's lifetime.

#### Scenario: Add mode with prior expenses shows the Recents section

- **WHEN** the user opens the Add Expense sheet for a budget that has at least one prior named, non-Add-Funds expense item
- **THEN** the screen renders a card titled "Recents" above the Amount card
- **AND** the card contains a horizontal scroll row of tappable tiles, one per candidate

#### Scenario: Add mode with no prior expenses hides the section

- **WHEN** the user opens the Add Expense sheet for a budget with no prior expense items (a brand-new budget)
- **THEN** the screen does not render the Recents card
- **AND** the form opens with the Amount card at the top of the scroll view

#### Scenario: Edit mode never shows the Recents section

- **WHEN** the user opens the Edit Expense sheet for an existing expense
- **THEN** the screen does not render the Recents card

### Requirement: Recents algorithm sorts by recency and dedupes by description

The candidate set surfaced in the Recents section SHALL be derived from `Budget.expenseItems` by:

1. Excluding Add Funds entries (`ExpenseItem.isAddFunds == true`) — they are not reusable as expense suggestions.
2. Excluding entries with no description (nil or whitespace-only `name`) — they are not actionable as suggestions.
3. Collapsing duplicates by description (case- AND diacritic-insensitive comparison after trimming whitespace, so "Café" / "cafe" / "CAFÉ" all collapse to one entry) — keeping only the most recent occurrence per unique description, with that occurrence's amount riding along.
4. Sorting the deduplicated set by date descending (most recent first).
5. Capping the result at an implementation-defined number.

The candidate set SHALL be computed at sheet-open and reused across keystrokes during typing; recomputing per-keystroke is forbidden because for budgets with many expenses, the sort would dominate the per-keystroke cost.

#### Scenario: Most recent occurrence per unique description wins

- **WHEN** the user opens Add Expense for a budget that has logged "Coffee" at $5.50 last week and "Coffee" at $6.00 yesterday
- **THEN** the Recents section shows one "Coffee" tile, showing $6.00 (the most recent occurrence's amount)

#### Scenario: Add Funds entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes both expense entries and Add Funds entries
- **THEN** the Recents section only surfaces the expense entries

#### Scenario: Unnamed entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes some expenses with no description
- **THEN** the Recents section only surfaces the named expenses

#### Scenario: Candidate set is capped at the implementation-defined limit

- **WHEN** the user opens Add Expense for a budget with more unique-named expenses than the implementation-defined cap
- **THEN** the Recents section surfaces no more than the cap, ordered most-recent-first

### Requirement: Tapping a Recents tile fills name + amount and resets Add Funds

A tap on a Recents tile SHALL write both `name` and `amount` to the draft (the in-memory `AddEditExpenseViewModel`) from the chosen suggestion AND SHALL reset the Add Funds toggle (`isAddFunds`) to off. A Recents tile represents a prior *expense*, so the toggle is reset to match that semantic; otherwise a user who toggled Add Funds on (and abandoned the action) would silently log the recent's positive amount as an add-funds adjustment. The tap SHALL NOT persist the expense — the user remains on the sheet to review and confirm via Save. The tap SHALL NOT alter the `date` field or other draft state.

#### Scenario: Tap fills name and amount but does not save

- **WHEN** the user taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field shows $5.50
- **AND** the user remains on the Add Expense sheet
- **AND** no `ExpenseItem` is persisted

#### Scenario: Tap resets the Add Funds toggle to off

- **WHEN** the user has the Add Funds toggle on, then taps a Recents tile
- **THEN** the Add Funds toggle becomes off
- **AND** the draft's `name` and `amount` are set from the tapped suggestion

### Requirement: Recents section filters as the user types into Description

The Recents candidate set SHALL filter in place as the user types into the Description field, using a case-insensitive substring match against each candidate's name. The section SHALL stay on the same surface as the form — no separate picker view, sheet, or screen is presented. The candidate set displayed SHALL be the cached candidate set filtered by the current query; the cache SHALL NOT be recomputed.

#### Scenario: Typing into Description narrows the Recents row

- **WHEN** the user opens Add Expense and the Recents section shows tiles for "Coffee", "Lunch", and "Groceries"
- **AND** the user types "co" into the Description field
- **THEN** the Recents row shows only the "Coffee" tile (substring match)

#### Scenario: Filter is case-insensitive

- **WHEN** the Recents section contains a "Coffee" tile
- **AND** the user types "COFFEE" into the Description field
- **THEN** the "Coffee" tile remains visible

#### Scenario: Filter is diacritic-insensitive

- **WHEN** the Recents section contains a "Café" tile
- **AND** the user types "cafe" into the Description field
- **THEN** the "Café" tile remains visible
- **AND** the same equivalence is used to dedup the candidate set, so the user never sees both "Café" and "cafe" as separate tiles

### Requirement: Filter-empty Recents preserves layout via a "No matches" placeholder

When the user types into Description and the resulting filter yields zero matches, the Recents card SHALL remain mounted with a placeholder labeled with the localized equivalent of "No matches". The placeholder SHALL occupy the same vertical space as a populated tile row, so the form below does not shift while the user types. This SHALL apply only when the bound budget has candidate expenses; if the candidate set is empty (true-empty), the section is absent (per the section-visibility requirement above).

#### Scenario: Filter yields no matches but the card stays mounted

- **WHEN** the user opens Add Expense on a budget with prior expenses
- **AND** the user types text that matches no candidate (e.g., "xyz")
- **THEN** the Recents card stays mounted at the same height
- **AND** displays the localized "No matches" placeholder
- **AND** the Amount card directly below does not shift vertically

### Requirement: Recents surface is accessible to VoiceOver and Dynamic Type users

Each tappable Recents tile SHALL expose a composed `accessibilityLabel` that announces both the description and the formatted amount, and an `accessibilityHint` that explains the tap action ("Fills the amount and description for review."). The trailing swipe-affordance icon (when shown) SHALL be hidden from VoiceOver (`accessibilityHidden(true)`) because its meaning is reproduced by VoiceOver's natural scroll-container behavior. The "No matches" placeholder SHALL expose an `accessibilityLabel` distinct from the visible glyph (e.g., "No matching recent expenses"). The phantom-content sizing anchor used by the placeholder SHALL be hidden from VoiceOver.

Tile geometry — the maximum tile width and the inner padding values — SHALL scale with Dynamic Type via `@ScaledMetric(relativeTo: .subheadline)` so the section remains legible at larger type sizes.

#### Scenario: VoiceOver reads a Recents tile as one combined element

- **WHEN** a VoiceOver user focuses a Recents tile labeled visually as "Coffee · $5.50"
- **THEN** VoiceOver announces a single combined label including both the name and the formatted amount
- **AND** announces the hint that explains the tap fills the draft for review

#### Scenario: Decorative swipe icon is silent to VoiceOver

- **WHEN** the Recents row contains the trailing swipe-affordance icon
- **THEN** VoiceOver does not announce the icon as a separate element

#### Scenario: Tile geometry scales with larger Dynamic Type sizes

- **WHEN** the user has set Dynamic Type to a larger size (e.g., `xxxLarge`)
- **THEN** the Recents tile maximum width and padding grow proportionally relative to the subheadline text style

### Requirement: Recents UI strings are keyed in Localizable.xcstrings

All user-facing strings introduced by the Recents surface SHALL be registered in `Localizable.xcstrings` under the `addEditExpense.recents.*` namespace, with translator-friendly `comment:` text describing the surface, context, and any interpolated arguments. The keys SHALL be translated to all 38 App Store storefront locales via the `translate-new-strings` skill before the change ships.

The keys SHALL include at minimum: the section title, the "No matches" placeholder copy, each accessibility label and hint introduced by the accessibility requirement, and any future-tense strings the implementation surfaces.

#### Scenario: All visible Recents strings have localization keys

- **WHEN** an auditor inspects the Recents surface source
- **THEN** no bare-literal `Text("…")` calls appear on user-visible strings under the `addEditExpense.recents.*` surface
- **AND** every string is a `String(localized:defaultValue:comment:)` call (or equivalent) under the `addEditExpense.recents.*` namespace

#### Scenario: Translations exist for all 38 storefront locales

- **WHEN** `python scripts/translate_catalog/check_translations.py` runs after the Recents work lands
- **THEN** the check passes with no missing or stale translations for any `addEditExpense.recents.*` key

### Requirement: Recents tile tap emits a Mixpanel `expense_recent_reused` event (F-8.02)

When the user taps a Recents tile, the app SHALL emit an `expense_recent_reused` analytics event via the injected `AnalyticsClient`. The event SHALL contain only categorical, non-PII properties per the analytics-spec.md §2.1 no-PII rule. The event SHALL include at minimum:

- The bound budget's period (`period`).
- A bucketed count of the number of Recents tiles visible when the tap happened (`recents_visible_count`).
- A bucketed position of the tapped tile in the visible row (`recents_tap_position`).
- A bucketed length of the typed Description query at tap time (`name_query_length`).

The event SHALL NOT include the description string, the amount value, or any user-identifying signal. Emission SHALL be subject to the user's consent state per analytics-spec.md §2.1 (same gating as `expense_logged` and `expense_edited`).

#### Scenario: Tap emits the analytics event with categorical properties

- **WHEN** the user taps a Recents tile in Add Expense on a daily budget
- **AND** the user has consented to analytics
- **THEN** the app emits an `expense_recent_reused` event
- **AND** the event includes `period: "daily"` (or its analytics-mapped equivalent)
- **AND** the event includes bucketed values for `recents_visible_count`, `recents_tap_position`, and `name_query_length`
- **AND** the event does not include the description string, the amount value, or any user identifier

#### Scenario: Tap does not emit when analytics consent is withheld

- **WHEN** the user has withheld analytics consent (or is in a consent-required jurisdiction without granting consent)
- **AND** the user taps a Recents tile
- **THEN** the app does not emit the `expense_recent_reused` event
- **AND** the draft fields are still populated (the analytics gate does not block the feature)

### Requirement: Successful Add-mode log feeds the rating-prompt coordinator

On a successful **Add-mode** expense save, the Add/Edit Expense screen SHALL notify the rating-prompt coordinator, passing whether the parent budget is in the active lifecycle state and whether the budget's current-period Remaining (computed from the existing budget calculator) is non-deficit after the save. This notification MUST occur only for successful Add-mode logs — not for edits, deletes, or save failures — and MUST NOT change the existing save, `expense_logged`, dismissal, or error-handling behavior.

#### Scenario: Add-mode save notifies the coordinator

- **WHEN** the user saves a new expense in Add mode and the save succeeds
- **THEN** the rating-prompt coordinator is notified with the active-state and non-deficit flags for the parent budget

#### Scenario: Edit-mode save does not notify the coordinator

- **WHEN** the user saves changes to an existing expense in Edit mode
- **THEN** the rating-prompt coordinator is not notified

#### Scenario: Failed save does not notify the coordinator

- **WHEN** an Add-mode save throws a persistence error
- **THEN** the rating-prompt coordinator is not notified and existing error handling is unchanged

