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

All `NSUbiquitousKeyValueStore` keys used by `AppSettings` SHALL be defined as `static let` constants on `AppSettings`. Key names SHALL be: `"defaultCarryOverEnabled"`, `"weekStartDay"`, and `"currencyDisplay"`.

#### Scenario: Keys are string constants

- **WHEN** the store keys are inspected
- **THEN** `AppSettings.defaultCarryOverEnabledKey` SHALL equal `"defaultCarryOverEnabled"`, `AppSettings.weekStartDayKey` SHALL equal `"weekStartDay"`, and `AppSettings.currencyDisplayKey` SHALL equal `"currencyDisplay"`.

---

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
