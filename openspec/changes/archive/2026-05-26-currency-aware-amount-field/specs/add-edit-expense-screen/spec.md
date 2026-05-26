## MODIFIED Requirements

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
- **THEN** the field renders the amount with no fraction digits

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

### Requirement: Toggling Add Funds on tints the amount text and currency prefix with Color.moneySurplus

When `AddEditExpenseViewModel.isAddFunds == true`, the Amount card's currency decoration `Text`(s) and the numeric `TextField` SHALL render with `.foregroundStyle(Color.moneySurplus)` (matching the green tint used by add-funds rows on the Budget detail screen). When `isAddFunds == false`, the decoration uses `.secondary` and the numeric field uses `.primary` (the existing styling). The tint SHALL apply to whichever side(s) the locale-correct currency decoration occupies (leading and/or trailing). The transition is driven reactively by the `@Observable` viewmodel and applies without explicit animation.

#### Scenario: Amount text tints green when Add Funds is on

- **WHEN** the user toggles Add Funds on
- **THEN** the currency decoration and the numeric field text render in `Color.moneySurplus`

#### Scenario: Amount text reverts to default colors when Add Funds is off

- **WHEN** the user toggles Add Funds off (from on)
- **THEN** the currency decoration renders in `.secondary` and the numeric field text renders in `.primary`
