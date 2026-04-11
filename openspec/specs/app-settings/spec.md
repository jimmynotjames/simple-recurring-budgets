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

All `NSUbiquitousKeyValueStore` keys used by `AppSettings` SHALL be defined as `static let` constants on `AppSettings`. Key names SHALL be: `"defaultCarryOverEnabled"` and `"weekStartDay"`.

#### Scenario: Keys are string constants

- **WHEN** the store keys are inspected
- **THEN** `AppSettings.defaultCarryOverEnabledKey` SHALL equal `"defaultCarryOverEnabled"` and `AppSettings.weekStartDayKey` SHALL equal `"weekStartDay"`.
