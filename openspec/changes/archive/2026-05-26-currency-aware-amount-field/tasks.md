<!-- Already implemented on branch fix/issue-34-currency-aware-amount-field (PR #121); tasks recorded complete. -->

## 1. Currency-aware format/parse style

- [x] 1.1 Add `currencyCode` + `locale` to `OptionalDecimalFormatStyle`; derive max fraction length from the currency's minor units (min 0)
- [x] 1.2 Replace `Decimal(string:locale:)` in `OptionalDecimalParseStrategy` with a locale-aware `Decimal.FormatStyle` parse so non-Western numerals are accepted; thread `locale` through

## 2. Locale-correct symbol affixes

- [x] 2.1 Replace `CurrencyDisplayPreference.prefix(for:)` with `affixes(for:locale:) -> (leading, trailing)`, deriving the split from the same currency `FormatStyle` as the display path (AttributedString run partitioning)

## 3. Wire the input views

- [x] 3.1 `AddEditBudgetView+AllocationCard`: render leading/trailing affixes around the field, pass `currencyCode` into the format style, mark affixes `accessibilityHidden`
- [x] 3.2 `AddEditExpenseView` amount field: same affix wiring + `currencyCode`; tint affixes with `Color.moneySurplus` when Add Funds is on
- [x] 3.3 Extract `AddEditExpenseView.amountCard` into `AddEditExpenseView+AmountCard.swift` to stay under the 600-line lint cap (relax `settings`/`isAmountFocused`/`sectionLabel` to internal)

## 4. Tests

- [x] 4.1 `OptionalDecimalFormatStyleTests`: per-currency fraction digits, locale separators, Arabic-Indic parse, format↔parse round-trip
- [x] 4.2 `CurrencyDisplayAffixesTests`: symbol side per locale (USD/en leading, EUR/fr trailing), affix↔display parity, code / codeAndSymbol
- [x] 4.3 Update the existing `OptionalDecimalFormatStyle()` call sites in `AddEditExpenseViewModelTests`

## 5. Cross-cutting + gate

- [x] 5.1 Accessibility: affixes `accessibilityHidden` (value announced by the field label) — verified
- [x] 5.2 No new user-facing strings (affixes come from formatters) → no translation run needed; no new Mixpanel events
- [x] 5.3 Run the four-step gate (`make format` → `make lint-fix` → `make build` → `make test`): 522 tests pass
