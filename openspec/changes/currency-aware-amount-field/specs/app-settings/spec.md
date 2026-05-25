## MODIFIED Requirements

### Requirement: CurrencyDisplayPreference enum

The system SHALL define a `CurrencyDisplayPreference` enum that is `String`-backed, `CaseIterable`, `Codable`, `Sendable`, and `Identifiable`. It SHALL have exactly three cases:

- `case symbol` with raw value `"symbol"`.
- `case code` with raw value `"code"`.
- `case codeAndSymbol` with raw value `"codeAndSymbol"`.

The enum SHALL expose:

- `var id: Self { self }` for `Identifiable` conformance.
- A localized `var label: String` providing a human-readable name per case ("Symbol", "Code", "Code + Symbol" in en).
- A `func example(locale: Locale) -> String` that returns a live preview of how a fixed sentinel amount renders under this preference in the supplied locale. The implementation SHALL: (a) resolve the example currency code via `locale.currency?.identifier`, falling back to `"USD"` if `nil` (mirroring `docs/product-features-planning.md` F-3.04 — "Defaults to locale's currency; USD if unable to determine at all"); (b) format `Decimal(25)` against that code and locale through the same `Decimal.formatted(currencyCode:display:locale:)` API the rest of the app uses, with `display` set to the case the method is called on. The example SHALL NOT be a hard-coded mock string. The `Locale` parameter SHOULD be defaulted to `Locale.autoupdatingCurrent` so production callers (the Settings picker) get the user's current locale and tests can supply a deterministic locale.
- A `func affixes(for currencyCode: String, locale: Locale) -> (leading: String, trailing: String)` that returns the currency symbol/code text to place around an editable amount field — NOT a full amount string. The leading/trailing split SHALL be derived from the same currency `FormatStyle` the display path uses (the `Decimal.formatted(currencyCode:display:locale:)` family), so symbol position and locale spacing match the rest of the app: text rendered before the numeric core is `leading`, text after it is `trailing` (e.g. `("$", "")` for USD in en_US, `("", " €")` for EUR in fr_FR). For `.codeAndSymbol`, the ISO code SHALL be kept leading and prepended to the symbol form. The `Locale` parameter SHOULD default to `Locale.autoupdatingCurrent`. This member replaces the former `prefix(for:)` accessor, which always returned a single leading string and could not represent trailing-symbol locales.

#### Scenario: All cases have correct raw values

- **WHEN** each `CurrencyDisplayPreference` case's `rawValue` is inspected
- **THEN** `symbol` SHALL be `"symbol"`, `code` SHALL be `"code"`, and `codeAndSymbol` SHALL be `"codeAndSymbol"`.

#### Scenario: CaseIterable conformance

- **WHEN** `CurrencyDisplayPreference.allCases` is iterated
- **THEN** it SHALL produce all three cases in declaration order: `[.symbol, .code, .codeAndSymbol]`.

#### Scenario: Identifiable conformance

- **WHEN** any `CurrencyDisplayPreference` value's `id` is read
- **THEN** the `id` SHALL equal the case itself (`Self`).

#### Scenario: Examples reflect the supplied locale's currency

- **WHEN** `CurrencyDisplayPreference.symbol.example(locale: Locale(identifier: "fr_FR"))` is called
- **THEN** it SHALL return the result of `Decimal(25).formatted(currencyCode: "EUR", display: .symbol, locale: Locale(identifier: "fr_FR"))` (i.e., the symbol-form rendering of 25 EUR in French formatting), and SHALL NOT return the en_US literal `"$25"`.

#### Scenario: Examples fall back to USD when the locale has no currency

- **WHEN** `CurrencyDisplayPreference.symbol.example(locale: someLocaleWithoutCurrency)` is called and `someLocaleWithoutCurrency.currency?.identifier` is `nil`
- **THEN** the method SHALL use `"USD"` as the currency code and SHALL return the result of `Decimal(25).formatted(currencyCode: "USD", display: .symbol, locale: someLocaleWithoutCurrency)`.

#### Scenario: Examples route through the formatter consistently across cases

- **WHEN** `example(locale:)` is called for each `CurrencyDisplayPreference` case with the same locale
- **THEN** each result SHALL equal `Decimal(25).formatted(currencyCode: code, display: <case>, locale: locale)` where `code` is the resolved currency identifier — i.e., `example` SHALL NOT diverge from the canonical formatter behavior.

#### Scenario: Affixes place the symbol on the locale-correct side

- **WHEN** `CurrencyDisplayPreference.symbol.affixes(for: "USD", locale: Locale(identifier: "en_US"))` is called
- **THEN** the `leading` part SHALL contain the `"$"` symbol and the `trailing` part SHALL be empty

- **WHEN** `CurrencyDisplayPreference.symbol.affixes(for: "EUR", locale: Locale(identifier: "fr_FR"))` is called
- **THEN** the `leading` part SHALL be empty and the `trailing` part SHALL contain the `"€"` symbol

#### Scenario: Affixes agree with the display formatter

- **WHEN** `affixes(for:locale:)` is called for a currency/locale pair and the corresponding amount is rendered via `Decimal.formatted(currencyCode:display:locale:)`
- **THEN** the rendered amount SHALL begin with the `leading` affix and end with the `trailing` affix
