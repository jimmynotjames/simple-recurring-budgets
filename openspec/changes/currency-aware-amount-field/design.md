## Context

The app has two paths for rendering money. The **display** path (`Decimal.formatted(currencyCode:display:locale:)`) was already correct: it uses a real `.currency` `FormatStyle`, so symbol position and per-currency fraction digits follow the locale. The **entry** path — a keypad-driven `TextField(value:format:)` shared by the Allocation (budget) and Amount (expense) fields — could not bake the symbol into its editable text, so it deliberately rendered the symbol as adjacent decoration and used a plain numeric `ParseableFormatStyle` (`OptionalDecimalFormatStyle`) for the editable value. That decoration was hard-coded leading, the numeric style was hard-coded to two fraction digits, and the parse strategy used `Decimal(string:locale:)`. The currency picker exposes all `Locale.commonISOCurrencyCodes`, so 0- and 3-decimal currencies and every numbering system are reachable.

## Goals / Non-Goals

**Goals:**
- The editable field agrees with the display path on fraction digits and symbol side, per locale and per currency.
- The field accepts the digits its own keyboard emits in every locale (no rejected keystrokes).
- Keep the symbol as adjacent decoration (not inside the editable text) so the `.decimalPad` experience is unchanged.

**Non-Goals:**
- No changes to the display path or any read-only money rendering — it is already correct.
- No currency conversion; changing a budget's currency still only relabels (F-3.04).
- No keypad restriction for 0-decimal currencies (see Decisions).

## Decisions

- **Derive fraction length from the currency, not a constant.** `OptionalDecimalFormatStyle` takes `currencyCode` + `locale` and reads the currency's minor-unit count from `NumberFormatter(numberStyle: .currency).maximumFractionDigits`. Minimum stays `0` so partial/blank input formats while typing. *Alternative considered:* hard-coding a small table of exceptions (JPY, BHD…) — rejected as incomplete and a maintenance burden versus letting the platform answer.

- **Derive the symbol affixes from the display formatter, not a second code path.** `CurrencyDisplayPreference.affixes(for:locale:)` formats a sentinel amount as an `AttributedString` through the *same* `.currency` style the display uses, then partitions runs on the number-part / number-symbol attributes: text before the numeric core is `leading`, text after is `trailing`. This guarantees the editor's symbol side and spacing match the display by construction, for any locale, including RTL (HStack mirrors via the environment). *Alternatives considered:* (a) a `leading`/`trailing` flag from `NumberFormatter.positivePrefix/Suffix` parsing — brittle around spacing; (b) putting the symbol inside the `TextField` via a currency style — breaks keypad editing. Replacing `prefix(for:)` outright (rather than adding alongside) avoids a misleading always-leading API lingering.

- **Parse through a locale-aware `FormatStyle`, not `Decimal(string:locale:)`.** `Decimal(string:locale:)` only understands Latin digits and returns `nil` for Arabic-Indic/Devanagari/etc., so parsing failed for the exact digits the keyboard produced. Parsing via `Decimal.FormatStyle(locale:)`'s strategy accepts whatever numbering system the matching formatter emits. Verified round-trip across `arab`, `arabext`, `deva`, `mymr`, and `latn`; it is also strictly more lenient than the old parser for Western partials (e.g. it even resolves grouping separators the old one mis-parsed).

- **Symbol decoration is `accessibilityHidden`.** The field's `accessibilityLabel` already announces the full formatted amount with currency, so the visible affix would be redundant for VoiceOver.

- **File split for the lint cap.** Extracting `AddEditExpenseView.amountCard` into `AddEditExpenseView+AmountCard.swift` (mirroring the existing `AddEditBudgetView+AllocationCard.swift`) keeps the view file under the 600-line strict-lint cap; this required relaxing `settings`, `isAmountFocused`, and `sectionLabel` to internal, matching the budget view's conventions.

## Risks / Trade-offs

- **0-decimal currencies round a typed decimal on commit** (e.g. `100.5` JPY → `101`) rather than blocking the separator at the keypad. → Accepted as the simpler, lower-risk option that matches currency semantics; keypad restriction is a possible follow-up.
- **Affix derivation depends on the `AttributedString` number-format attributes** (`numberPart`, `numberSymbol`). → Low risk: these are stable Foundation APIs; covered by an affix↔display parity test so a behavior change would fail CI.
- **`codeAndSymbol` has no native `FormatStyle` presentation** (it is an app-specific concat). → The ISO code is kept leading and prepended to the symbol form; documented in the affix helper.

## Migration Plan

No data or schema migration. Pure formatting/parsing behavior change behind existing UI. Rollback is reverting the change set; no persisted state is affected.
