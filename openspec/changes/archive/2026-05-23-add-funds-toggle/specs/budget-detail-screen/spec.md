## MODIFIED Requirements

### Requirement: Each expense row displays name, formatted relative date, amount, and Add-Funds visual treatment

The private `ExpenseRowView` SHALL render an `HStack` with:

- A leading `VStack(alignment: .leading)` containing:
  - The expense name in body font (up to 3 lines), or — if `name == nil` — an italicized placeholder body-font caption keyed `budgetDetail.expenseRow.unnamed` (en-US "Untitled") in secondary foreground. The placeholder copy is intentionally type-neutral so the same key reads naturally for both expense rows and add-funds rows.
  - The expense `date` formatted via `Date.formattedForExpenseList()` (Today / Yesterday / locale-aware date+time) in caption font with secondary foreground.
- A trailing amount label rendering `expense.displayAmount` (the absolute value of `expense.amount`) formatted with the budget's `currencyCode` and `AppSettings.currencyDisplay`, in body font with `monospacedDigit`. When `expense.isAddFunds == true` (i.e. `expense.amount < 0`), the amount foreground SHALL be `Color.moneySurplus`; otherwise the primary text color.

Row vertical padding SHALL scale via `@ScaledMetric` relative to `.body`.

The row SHALL collapse to a single accessibility element via `accessibilityElement(children: .combine)` and provide the composed label specified by the next requirement.

#### Scenario: Named expense row renders name, date, and amount

- **WHEN** an expense has a non-nil `name`
- **THEN** the row shows the name (body font, up to 3 lines), the formatted relative date (caption, secondary), and the formatted absolute amount (body, monospacedDigit, primary color)

#### Scenario: Unnamed expense row uses italic placeholder

- **WHEN** an expense has `name == nil`
- **THEN** the row shows the italicized localized "Untitled" placeholder (key `budgetDetail.expenseRow.unnamed`) in secondary foreground in place of the name

#### Scenario: Add-funds row uses surplus color

- **WHEN** an expense has `amount < 0` (i.e. `isAddFunds == true`, F-6.01 display path)
- **THEN** the trailing amount text uses `Color.moneySurplus` and renders the absolute value of the amount

#### Scenario: Unnamed add-funds row uses the same type-neutral placeholder

- **WHEN** an add-funds row has `name == nil`
- **THEN** the row shows the same italicized "Untitled" placeholder (key `budgetDetail.expenseRow.unnamed`) as an unnamed expense row — there is no separate add-funds-specific placeholder

### Requirement: Each expense row provides a composed VoiceOver label distinguishing add-funds from expenses

The combined accessibility element SHALL provide a localized label that includes the formatted absolute amount, the expense name (or the localized "Untitled" placeholder when nil), and the formatted relative date. The label SHALL use distinct keys for the two semantic cases:

- `budgetDetail.expenseRow.accessibilityLabel` for `isAddFunds == false` (en-US: "%@, %@, %@" — amount, name, date).
- `budgetDetail.expenseRow.accessibilityLabel.addFunds` for `isAddFunds == true` (en-US: "%@ added, %@, %@" — amount, name, date).

#### Scenario: Expense row VoiceOver label

- **WHEN** VoiceOver focuses a row whose `expense.amount > 0`
- **THEN** the announced label uses key `budgetDetail.expenseRow.accessibilityLabel` and contains the formatted absolute amount, the resolved name (or "Untitled"), and the formatted relative date

#### Scenario: Add-funds row VoiceOver label

- **WHEN** VoiceOver focuses a row whose `expense.amount < 0`
- **THEN** the announced label uses key `budgetDetail.expenseRow.accessibilityLabel.addFunds` and contains the formatted absolute amount followed by "added" (per the catalog string), then the resolved name and date
