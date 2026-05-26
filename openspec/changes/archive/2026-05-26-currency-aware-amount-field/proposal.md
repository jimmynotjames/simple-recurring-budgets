## Why

The money **display** path already formats through a proper currency `FormatStyle`, but the money **entry** path (the Allocation field on Add/Edit Budget and the Amount field on Add/Edit Expense) diverged from it: it formatted with a plain `.number` style capped at two fraction digits and pinned the currency symbol to the leading edge. This truncated 3-decimal currencies (BHD/KWD) on edit, accepted nonexistent minor units for 0-decimal currencies (JPY), and placed the symbol on the wrong side in trailing-symbol locales (e.g. `€ 25` instead of `25,00 €` in French). A related, pre-existing bug made the field reject every keystroke in locales whose `.decimalPad` emits non-Western digits (Arabic-Indic in ar_EG/ar_SA, etc.), because the parser only understood Latin numerals. All three undermine F-3.04 (per-budget currency, locale-correct formatting) and the project's all-languages i18n commitment.

## What Changes

- The shared amount-entry format style derives its **maximum fraction length from the currency's minor units** (JPY→0, USD→2, BHD→3) instead of a hard-coded `0...2`; the minimum stays `0` so partial typing keeps working.
- The currency symbol shown beside the field is now **placed on the locale-correct side** (leading or trailing, including locale spacing), derived from the same currency `FormatStyle` the display path uses, and mirrors correctly in RTL. **BREAKING (internal API):** `CurrencyDisplayPreference.prefix(for:)` is replaced by `affixes(for:locale:) -> (leading: String, trailing: String)`.
- The amount-entry parser now reads **any numbering system the formatter can produce** (Arabic-Indic, Extended Arabic-Indic, Devanagari, Myanmar, Latin, …) via a locale-aware parse strategy, fixing the rejected-keystroke bug. It remains at least as lenient as before for Western input.
- The symbol decoration is marked `accessibilityHidden`; the field's existing accessibility label already announces the full formatted amount.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `add-edit-budget-screen`: the Allocation field requirement — fraction precision becomes currency-aware, and the leading "currency prefix" becomes a locale-correct leading/trailing affix; "currency prefix" scenarios updated and a trailing-symbol-locale scenario added.
- `add-edit-expense-screen`: the Amount field requirement — same fraction-precision and affix changes; the stale `prefix(for:)` reference is replaced; a scenario for non-Western-digit (e.g. Arabic-Indic) parsing is added.
- `app-settings`: the `CurrencyDisplayPreference` enum requirement — documents the new `affixes(for:locale:)` member (replacing `prefix(for:)`) alongside `label` and `example(locale:)`.

## Impact

- Code: `Formatting/OptionalDecimalFormatStyle.swift`, `Formatting/CurrencyDisplayPreference.swift`, `Views/AddEditBudgetView+AllocationCard.swift`, `Views/AddEditExpenseView.swift` (+ extracted `Views/AddEditExpenseView+AmountCard.swift`).
- Tests: `OptionalDecimalFormatStyleTests`, `CurrencyDisplayAffixesTests`; one updated call site in `AddEditExpenseViewModelTests`.
- No schema, persistence, or CloudKit impact. No new user-facing strings, so no translation work. No new analytics events.
- Already implemented on branch `fix/issue-34-currency-aware-amount-field` (PR #121); 522 tests pass.

## Doc alignment

- `docs/product-features-planning.md` F-3.04 (per-budget currency; "defaults to locale's currency"): this change strengthens conformance — no F-3.04 text change required.
- `docs/main-prd.md` / `docs/tech-design-doc.md`: no global-constraint, architecture, schema, or sync changes. No doc updates needed.
