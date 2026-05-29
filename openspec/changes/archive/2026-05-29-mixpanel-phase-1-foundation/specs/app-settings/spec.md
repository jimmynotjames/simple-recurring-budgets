## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Key constants

All `NSUbiquitousKeyValueStore` keys used by `AppSettings` SHALL be defined as `static let` constants on `AppSettings`. Key names SHALL be: `"defaultCarryOverEnabled"`, `"weekStartDay"`, `"currencyDisplay"`, `"analyticsOptIn"`, and `"analyticsDistinctId"`.

#### Scenario: Keys are string constants

- **WHEN** the store keys are inspected
- **THEN** `AppSettings.defaultCarryOverEnabledKey` SHALL equal `"defaultCarryOverEnabled"`, `AppSettings.weekStartDayKey` SHALL equal `"weekStartDay"`, `AppSettings.currencyDisplayKey` SHALL equal `"currencyDisplay"`, `AppSettings.analyticsOptInKey` SHALL equal `"analyticsOptIn"`, and `AppSettings.analyticsDistinctIdKey` SHALL equal `"analyticsDistinctId"`.
