# App settings

App-wide preferences persisted via `NSUbiquitousKeyValueStore`, with iCloud sync across the user's devices. Synced from change `app-settings` (2026-04-11).
## Requirements
### Requirement: Weekday enum

The system SHALL define a `Weekday` enum that is `Int`-backed, `CaseIterable`, `Codable`, and `Identifiable` with cases `sunday = 1`, `monday = 2`, `tuesday = 3`, `wednesday = 4`, `thursday = 5`, `friday = 6`, `saturday = 7`. Raw values SHALL match Foundation's `Calendar.firstWeekday` convention.

`Weekday` SHALL provide a static initializer `from(calendarFirstWeekday:)` that accepts an `Int` and returns the corresponding `Weekday`, or `nil` if the value is out of range (not 1–7).

#### Scenario: All cases have correct raw values

- **WHEN** each `Weekday` case's `rawValue` is inspected
- **THEN** `sunday` SHALL be `1`, `monday` SHALL be `2`, `tuesday` SHALL be `3`, `wednesday` SHALL be `4`, `thursday` SHALL be `5`, `friday` SHALL be `6`, `saturday` SHALL be `7`.

#### Scenario: Initializer from Calendar.firstWeekday

- **WHEN** `Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday)` is called
- **THEN** it SHALL return a non-nil `Weekday` matching the locale's first day of week.

#### Scenario: Initializer rejects out-of-range values

- **WHEN** `Weekday.from(calendarFirstWeekday: 0)` or `Weekday.from(calendarFirstWeekday: 8)` is called
- **THEN** it SHALL return `nil`.

#### Scenario: CaseIterable and Identifiable conformance

- **WHEN** `Weekday.allCases` is iterated
- **THEN** it SHALL produce all seven cases in order from `sunday` through `saturday`, and each case's `id` SHALL be its `rawValue`.

---

### Requirement: AppSettings class

The system SHALL define an `@Observable final class AppSettings` that persists app-wide settings to `NSUbiquitousKeyValueStore`, enabling automatic iCloud sync across the user's devices signed into the same Apple ID. The class SHALL accept a backing store via `init(store: KeyValueStore = NSUbiquitousKeyValueStore.default)` where `KeyValueStore` is a protocol abstracting the store's read/write/synchronize interface for testability.

#### Scenario: Default initialization

- **WHEN** `AppSettings()` is created with no arguments
- **THEN** it SHALL use `NSUbiquitousKeyValueStore.default` as its backing store.

#### Scenario: Custom store for testing

- **WHEN** `AppSettings(store: someTestStore)` is created with a mock `KeyValueStore`
- **THEN** all reads and writes SHALL use `someTestStore`, not `.default`.

---

### Requirement: KeyValueStore protocol

The system SHALL define a `KeyValueStore` protocol with methods matching the subset of `NSUbiquitousKeyValueStore` used by `AppSettings`: reading values by key, writing values by key, and `synchronize()`. `NSUbiquitousKeyValueStore` SHALL conform to this protocol via extension. An in-memory implementation SHALL be available for unit tests.

#### Scenario: NSUbiquitousKeyValueStore conforms

- **WHEN** `NSUbiquitousKeyValueStore.default` is used where `KeyValueStore` is expected
- **THEN** it SHALL compile and function without additional adapter code.

#### Scenario: In-memory store for tests

- **WHEN** a test creates an in-memory `KeyValueStore`
- **THEN** reads and writes SHALL work in isolation without touching `NSUbiquitousKeyValueStore` or iCloud.

---

### Requirement: defaultCarryOverEnabled setting

`AppSettings` SHALL expose a `defaultCarryOverEnabled` property of type `Bool`. The default value SHALL be `true`. Changes to this property SHALL be persisted to `NSUbiquitousKeyValueStore` under the key `"defaultCarryOverEnabled"` and SHALL trigger `@Observable` change notifications. The value SHALL sync across the user's iCloud-connected devices.

#### Scenario: Default value on fresh store

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"defaultCarryOverEnabled"`
- **THEN** `defaultCarryOverEnabled` SHALL be `true`.

#### Scenario: Persisted value is read on init

- **WHEN** a store has `"defaultCarryOverEnabled"` set to `false`, and `AppSettings` is initialized with that store
- **THEN** `defaultCarryOverEnabled` SHALL be `false`.

#### Scenario: Setting persists to store

- **WHEN** `settings.defaultCarryOverEnabled` is set to `false`
- **THEN** the backing store SHALL contain `false` for key `"defaultCarryOverEnabled"`.

#### Scenario: Observable change notification

- **WHEN** `settings.defaultCarryOverEnabled` is changed
- **THEN** SwiftUI views observing `AppSettings` SHALL be notified of the change.

---

### Requirement: weekStartDay setting

`AppSettings` SHALL expose a `weekStartDay` property of type `Weekday`. The default value SHALL be derived from `Calendar.current.firstWeekday` (the locale's conventional first day of the week). Changes to this property SHALL be persisted to `NSUbiquitousKeyValueStore` under the key `"weekStartDay"` (stored as the `Weekday` raw `Int` value) and SHALL trigger `@Observable` change notifications. The value SHALL sync across the user's iCloud-connected devices.

#### Scenario: Default value matches locale

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"weekStartDay"`
- **THEN** `weekStartDay` SHALL equal the `Weekday` corresponding to `Calendar.current.firstWeekday`.

#### Scenario: Persisted value is read on init

- **WHEN** a store has `"weekStartDay"` set to `2` (Monday), and `AppSettings` is initialized with that store
- **THEN** `weekStartDay` SHALL be `.monday`.

#### Scenario: Setting persists to store

- **WHEN** `settings.weekStartDay` is set to `.monday`
- **THEN** the backing store SHALL contain `2` for key `"weekStartDay"`.

#### Scenario: Invalid stored value falls back to locale default

- **WHEN** a store has `"weekStartDay"` set to `99`, and `AppSettings` is initialized with that store
- **THEN** `weekStartDay` SHALL fall back to the locale's `Calendar.current.firstWeekday`.

#### Scenario: Observable change notification

- **WHEN** `settings.weekStartDay` is changed
- **THEN** SwiftUI views observing `AppSettings` SHALL be notified of the change.

---

### Requirement: External-change observation

`AppSettings` SHALL observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` to detect changes pushed from another device. When a notification arrives, the class SHALL re-read the changed keys and update the corresponding stored properties, triggering `@Observable` change notifications so the UI reflects the latest synced values.

#### Scenario: Another device changes defaultCarryOverEnabled

- **WHEN** a `didChangeExternallyNotification` arrives with `"defaultCarryOverEnabled"` among the changed keys
- **THEN** `settings.defaultCarryOverEnabled` SHALL update to the new value from the store.

#### Scenario: Another device changes weekStartDay

- **WHEN** a `didChangeExternallyNotification` arrives with `"weekStartDay"` among the changed keys
- **THEN** `settings.weekStartDay` SHALL update to the new value from the store.

#### Scenario: UI updates on external change

- **WHEN** a property updates due to an external-change notification
- **THEN** SwiftUI views observing `AppSettings` SHALL re-render with the updated value.

---

### Requirement: Environment injection

`AppSettings` SHALL be injected into the SwiftUI environment from the app entry point (`simple_recurring_budgetsApp`). Views SHALL access it via `@Environment(AppSettings.self)`.

#### Scenario: AppSettings available in view hierarchy

- **WHEN** any view in the app's `WindowGroup` accesses `@Environment(AppSettings.self)`
- **THEN** it SHALL receive the shared `AppSettings` instance.

---

### Requirement: Key constants

All `NSUbiquitousKeyValueStore` keys used by `AppSettings` SHALL be defined as `static let` constants on `AppSettings`. Key names SHALL be: `"defaultCarryOverEnabled"`, `"weekStartDay"`, `"currencyDisplay"`, `"analyticsOptIn"`, and `"analyticsDistinctId"`.

#### Scenario: Keys are string constants

- **WHEN** the store keys are inspected
- **THEN** `AppSettings.defaultCarryOverEnabledKey` SHALL equal `"defaultCarryOverEnabled"`, `AppSettings.weekStartDayKey` SHALL equal `"weekStartDay"`, `AppSettings.currencyDisplayKey` SHALL equal `"currencyDisplay"`, `AppSettings.analyticsOptInKey` SHALL equal `"analyticsOptIn"`, and `AppSettings.analyticsDistinctIdKey` SHALL equal `"analyticsDistinctId"`.

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

### Requirement: analyticsOptIn setting

`AppSettings` SHALL expose an `analyticsOptIn` property of type `Bool`. The default value SHALL be **locale-aware**, resolved on first read from `ConsentJurisdiction.kind(for: Locale.current.region)` (see the `product-analytics` capability):

- `.required` jurisdiction → default `false`.
- `.auto_optin` jurisdiction → default `true`.

The resolved default SHALL NOT be persisted to the backing store on first read. Persistence SHALL occur only on the first explicit user action that writes the property — either a Settings toggle change OR a first-run consent sheet decision (accept / decline). This preserves the "first-launch default each device experiences is the correct one for its own locale" invariant when devices in different jurisdictions share the same iCloud account.

When the property is written (toggle or consent decision), the value SHALL be persisted to `NSUbiquitousKeyValueStore` under the key `"analyticsOptIn"` and SHALL trigger `@Observable` change notifications. The value SHALL sync across the user's iCloud-connected devices.

`AppSettings` SHALL also expose a `static let analyticsOptInKey = "analyticsOptIn"` constant alongside the existing key constants.

`AppSettings` SHALL expose a derived read-only flag (`var analyticsOptInExplicitlySet: Bool` or equivalent) that returns `true` when the backing store contains a value for `"analyticsOptIn"` and `false` otherwise. This flag is consumed by the first-run consent sheet trigger in the `product-analytics` capability.

#### Scenario: Default value in strict-opt-in jurisdiction (no persisted value)

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"analyticsOptIn"`, and `Locale.current.region` is in the strict-opt-in table (e.g., `DE`)
- **THEN** `analyticsOptIn` SHALL return `false`

#### Scenario: Default value in auto-opt-in jurisdiction (no persisted value)

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"analyticsOptIn"`, and `Locale.current.region` is not in the strict-opt-in table (e.g., `US`)
- **THEN** `analyticsOptIn` SHALL return `true`

#### Scenario: Default value is not persisted on read

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"analyticsOptIn"`, and `analyticsOptIn` is read
- **THEN** the backing store SHALL still contain no value for `"analyticsOptIn"` after the read

#### Scenario: Persisted value overrides locale default

- **WHEN** the backing store contains `"analyticsOptIn" = true` and the device locale is `DE` (strict-opt-in)
- **THEN** `analyticsOptIn` SHALL return `true` (the persisted value), not the locale default `false`

#### Scenario: Setting persists to store

- **WHEN** `settings.analyticsOptIn = true` is written
- **THEN** the backing store SHALL contain `true` under the key `"analyticsOptIn"`

#### Scenario: analyticsOptInExplicitlySet reflects backing store presence

- **WHEN** the backing store has no value for `"analyticsOptIn"`, then `settings.analyticsOptIn = true` is written
- **THEN** `analyticsOptInExplicitlySet` SHALL transition from `false` to `true`

#### Scenario: Observable change notification

- **WHEN** `settings.analyticsOptIn` is changed
- **THEN** SwiftUI views observing `AppSettings` SHALL be notified of the change

#### Scenario: External change updates the property

- **WHEN** a `NSUbiquitousKeyValueStore.didChangeExternallyNotification` arrives with `"analyticsOptIn"` among the changed keys (`NSUbiquitousKeyValueStoreChangedKeysKey`)
- **THEN** `settings.analyticsOptIn` SHALL update to the new value from the store, and SwiftUI views observing `AppSettings` SHALL re-render

---

### Requirement: analyticsDistinctId setting

`AppSettings` SHALL expose an `analyticsDistinctId` property of type `String`. The value SHALL be a UUIDv4 string generated on first read if no value is persisted under the key `"analyticsDistinctId"`. The generated value SHALL be written to the backing store immediately (followed by `synchronize()`) so subsequent reads on the same device — and on iCloud-paired devices once the key syncs — return the same value.

The setter SHALL be `internal` or `private(set)`; no caller outside `AppSettings` SHALL overwrite the value. Reads from outside `AppSettings` are allowed.

`AppSettings` SHALL also expose a `static let analyticsDistinctIdKey = "analyticsDistinctId"` constant alongside the existing key constants.

The property SHALL trigger `@Observable` change notifications when an external write (from another iCloud-paired device) propagates via `didChangeExternallyNotification`.

The UUID SHALL be generated using `UUID().uuidString` (lower- or upper-case both acceptable; the implementation SHALL be stable across reads).

#### Scenario: Generates a UUID on first read with empty store

- **WHEN** `AppSettings` is initialized with a store that has no stored value for `"analyticsDistinctId"`, and `analyticsDistinctId` is read
- **THEN** the read SHALL return a non-empty string in canonical UUID format (e.g., `"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"`), and the same value SHALL be persisted to the backing store

#### Scenario: Persisted value is read on subsequent reads

- **WHEN** `analyticsDistinctId` was previously read and persisted, and `AppSettings` is initialized again with the same store
- **THEN** `analyticsDistinctId` SHALL return the previously-persisted value

#### Scenario: External change updates the property

- **WHEN** a `NSUbiquitousKeyValueStore.didChangeExternallyNotification` arrives with `"analyticsDistinctId"` among the changed keys
- **THEN** `settings.analyticsDistinctId` SHALL update to the new value from the store, and SwiftUI views observing `AppSettings` SHALL re-render

#### Scenario: Setter is not exposed publicly

- **WHEN** an external module attempts to assign to `settings.analyticsDistinctId`
- **THEN** the assignment SHALL NOT be allowed by the `AppSettings` access modifiers (compile-time enforcement, e.g. `private(set)` or `internal(set)` paired with module boundary)

