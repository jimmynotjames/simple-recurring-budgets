<!--
  This delta extends the existing `app-settings` capability (synced from change
  `app-settings`, 2026-04-11) with a new currency-display preference. No
  existing requirements are modified or removed; only ADDED requirements.

  After this change archives, the synced `app-settings` spec.md will gain:
  - A new "CurrencyDisplayPreference enum" requirement.
  - A new "currencyDisplay setting" requirement.
  - The "External-change observation" and "Key constants" sections will read
    naturally as the new key joins the existing two; this delta does not need
    to MODIFY those sections because the original text describes an open-ended
    pattern. The implementation, however, will extend the observer's branch
    set to include the new key (covered as a scenario below).
-->

## ADDED Requirements

### Requirement: CurrencyDisplayPreference enum

The system SHALL define a `CurrencyDisplayPreference` enum that is `String`-backed, `CaseIterable`, `Codable`, `Sendable`, and `Identifiable`. It SHALL have exactly three cases:

- `case symbol` with raw value `"symbol"`.
- `case code` with raw value `"code"`.
- `case codeAndSymbol` with raw value `"codeAndSymbol"`.

The enum SHALL expose:

- `var id: Self { self }` for `Identifiable` conformance.
- A localized `var label: String` providing a human-readable name per case ("Symbol", "Code", "Code + Symbol" in en).
- A `func example(locale: Locale) -> String` that returns a live preview of how a fixed sentinel amount renders under this preference in the supplied locale. The implementation SHALL: (a) resolve the example currency code via `locale.currency?.identifier`, falling back to `"USD"` if `nil` (mirroring `docs/product-features-planning.md` F-3.04 — "Defaults to locale's currency; USD if unable to determine at all"); (b) format `Decimal(25)` against that code and locale through the same `Decimal.formatted(currencyCode:display:locale:)` API the rest of the app uses, with `display` set to the case the method is called on. The example SHALL NOT be a hard-coded mock string. The `Locale` parameter SHOULD be defaulted to `Locale.autoupdatingCurrent` so production callers (the Settings picker) get the user's current locale and tests can supply a deterministic locale.

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

---

### Requirement: currencyDisplay setting

`AppSettings` SHALL expose a `currencyDisplay` property of type `CurrencyDisplayPreference`. The default value SHALL be `.symbol`. Changes to this property SHALL be persisted to `NSUbiquitousKeyValueStore` under the key `"currencyDisplay"` (stored as the enum's `String` raw value) and SHALL trigger `@Observable` change notifications. The value SHALL sync across the user's iCloud-connected devices.

If the backing store contains a value for `"currencyDisplay"` that is not one of the three recognized raw values (e.g., a future value written by a newer app version), the system SHALL fall back to `.symbol` and SHALL NOT crash. The unrecognized value SHALL remain in the store untouched until a recognized write replaces it, so a newer app version on another paired device retains its preference.

The `KeyValueStore` protocol SHALL include a `func set(_ value: String, forKey defaultName: String)` method to support persisting the enum's raw value. Both `NSUbiquitousKeyValueStore` (via existing inherited API) and the in-memory `MockKeyValueStore` SHALL conform.

`AppSettings` SHALL also expose a `static let currencyDisplayKey = "currencyDisplay"` constant alongside the existing key constants, mirroring the convention established by `defaultCarryOverEnabledKey` and `weekStartDayKey`.

#### Scenario: Default value on fresh store

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"currencyDisplay"`
- **THEN** `currencyDisplay` SHALL be `.symbol`.

#### Scenario: Persisted value is read on init

- **WHEN** a store has `"currencyDisplay"` set to `"code"`, and `AppSettings` is initialized with that store
- **THEN** `currencyDisplay` SHALL be `.code`.

#### Scenario: Setting persists to store

- **WHEN** `settings.currencyDisplay` is set to `.codeAndSymbol`
- **THEN** the backing store SHALL contain `"codeAndSymbol"` for key `"currencyDisplay"`.

#### Scenario: Invalid stored value falls back to default

- **WHEN** a store has `"currencyDisplay"` set to `"unknownFutureValue"`, and `AppSettings` is initialized with that store
- **THEN** `currencyDisplay` SHALL be `.symbol` (the default), and the store value SHALL NOT be overwritten by initialization.

#### Scenario: Observable change notification

- **WHEN** `settings.currencyDisplay` is changed
- **THEN** SwiftUI views observing `AppSettings` SHALL be notified of the change.

#### Scenario: External change updates the property

- **WHEN** a `NSUbiquitousKeyValueStore.didChangeExternallyNotification` arrives with `"currencyDisplay"` among the changed keys (`NSUbiquitousKeyValueStoreChangedKeysKey`)
- **THEN** `settings.currencyDisplay` SHALL update to the new value from the store, and SwiftUI views observing `AppSettings` SHALL re-render.

#### Scenario: External change with nil changed-keys list reloads currencyDisplay

- **WHEN** a `NSUbiquitousKeyValueStore.didChangeExternallyNotification` arrives with no `NSUbiquitousKeyValueStoreChangedKeysKey` entry (signaling "reload all")
- **THEN** `settings.currencyDisplay` SHALL be re-read from the store alongside the existing keys.

#### Scenario: Key constant value

- **WHEN** the `AppSettings.currencyDisplayKey` constant is inspected
- **THEN** it SHALL equal the string `"currencyDisplay"`.
