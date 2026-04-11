## Context

The app needs persistent, app-wide settings that are readable from both SwiftUI views and non-view business logic (e.g., Budget creation) and that sync across the user's devices via iCloud. Two settings are confirmed by the product spec: `defaultCarryOverEnabled` (F-2.07) and `weekStartDay` (F-5.01). These are not user data (they don't belong in SwiftData/CloudKit) — they are lightweight preferences stored in `NSUbiquitousKeyValueStore` so they automatically sync to every device signed into the same iCloud account.

Currently, `Budget.swift` has a TODO noting that `isCarryOverEnabled` should pull its initial value from a persisted setting. No settings infrastructure exists yet.

## Goals / Non-Goals

**Goals:**

- Provide a single, centralized class (`AppSettings`) that owns all `NSUbiquitousKeyValueStore`-backed settings.
- Make settings reactive for SwiftUI (view updates when a setting changes) via `@Observable`.
- Sync settings across the user's iCloud-connected devices automatically.
- Handle external-change notifications (`NSUbiquitousKeyValueStore.didChangeExternallyNotification`) so local state stays current when another device writes.
- Make settings accessible from services and view models, not just views.
- Make settings testable via a protocol abstraction over `NSUbiquitousKeyValueStore`.
- Introduce a type-safe `Weekday` enum for start-of-week configuration.

**Non-Goals:**

- No Settings UI — this change is persistence layer only.
- No color theme settings — deferred until F-4.01/02 specs are written.
- No migration from prior `UserDefaults` keys (none exist yet).
- `weekStartDay` does not cascade to existing budget period-boundary calculations in this change — that wiring happens in a future F-5.01 implementation change.

## Decisions

### 1. `NSUbiquitousKeyValueStore` instead of `UserDefaults`

**Choice:** Use `NSUbiquitousKeyValueStore` as the backing store so settings sync across the user's iCloud devices.

**Alternatives considered:**
- `UserDefaults` — rejected because it is device-local; the user would need to re-configure settings on each device.
- SwiftData/CloudKit model — rejected because these are lightweight key-value preferences, not relational data; adding them to the SwiftData schema adds unnecessary complexity and migration burden.

**Trade-off:** `NSUbiquitousKeyValueStore` has a 1 MB / 1024 key limit. Acceptable for a small number of app-wide preferences; if settings grow past dozens, revisit.

### 2. `@Observable` class with stored properties + `didSet` persistence

**Choice:** `AppSettings` is an `@Observable final class`. Each setting is a stored Swift property. The `init` loads values from the store; each `didSet` writes back and calls `synchronize()`. The class also observes `NSUbiquitousKeyValueStore.didChangeExternallyNotification` to update local properties when another device writes.

**Alternatives considered:**
- `@AppStorage` in views — rejected because business logic (Budget init, carry-over boundary math) cannot access view-scoped property wrappers. `@AppStorage` also does not support `NSUbiquitousKeyValueStore`.
- Computed properties wrapping the store — rejected because `@Observable` only tracks stored properties automatically; computed properties reading from an external store would not trigger SwiftUI observation.
- Static properties on a namespace — rejected because they're not reactive and not testable.

### 3. `Weekday` enum (Int-backed, 1–7)

**Choice:** A `Weekday` enum with `Int` raw values 1 (Sunday) through 7 (Saturday), matching Foundation's `Calendar.firstWeekday` convention. `CaseIterable` and `Identifiable` for future picker UI.

**Alternatives considered:**
- Raw `Int` stored directly — rejected because it admits invalid values (0, 8+) and is not self-documenting at call sites.

### 4. Protocol abstraction for testability

**Choice:** Define a `KeyValueStore` protocol with the subset of `NSUbiquitousKeyValueStore` methods used by `AppSettings` (`object(forKey:)`, `set(_:forKey:)`, `synchronize()`). `NSUbiquitousKeyValueStore` conforms via extension. Tests use an in-memory implementation.

**Rationale:** `NSUbiquitousKeyValueStore` cannot be instantiated with a custom suite like `UserDefaults(suiteName:)`, so a protocol seam is the standard isolation technique. This also future-proofs for App Group scenarios.

### 5. External-change observation

**Choice:** `AppSettings.init` registers for `NSUbiquitousKeyValueStore.didChangeExternallyNotification`. On receipt, it re-reads changed keys and updates stored properties, which automatically triggers `@Observable` change notifications for SwiftUI.

**Rationale:** Without this, a device that receives a sync update from iCloud would show stale setting values until the next app launch.

### 6. Environment injection from app entry point

**Choice:** `simple_recurring_budgetsApp` creates `@State var settings = AppSettings()` and injects via `.environment(settings)`. Views access via `@Environment(AppSettings.self)`.

**Rationale:** Aligns with MVVM + `@Observable` architecture from tech-design-doc. Single owner, shared across the view hierarchy.

### 7. Key naming

**Choice:** Static constants on `AppSettings` (e.g., `static let defaultCarryOverEnabledKey = "defaultCarryOverEnabled"`). Keeps keys discoverable and avoids typo drift. Same key names work in `NSUbiquitousKeyValueStore` as previously planned for `UserDefaults`.

### 8. Default value strategy

**Choice:** `NSUbiquitousKeyValueStore` returns `0` / `false` / `nil` for unset keys (no `register(defaults:)` equivalent). `AppSettings.init` checks whether a key exists before reading; if absent, uses the hard-coded default (`true` for carry-over, locale `firstWeekday` for week start).

## Risks / Trade-offs

- **Risk:** `didSet` fires during `init` property assignment in some Swift versions. → **Mitigation:** Load into locals first, then assign to `self.property` after the `init` body, or use a `_isInitializing` flag to skip writes during init.
- **Risk:** `@Observable` macro may interact unexpectedly with `didSet`. → **Mitigation:** Unit test that changing a property on `AppSettings` both persists to the store and triggers observation. If `didSet` is swallowed by the macro, use `willSet`/manual `access`/`withMutation` approach.
- **Risk:** `NSUbiquitousKeyValueStore` sync is eventual and can be delayed. → **Mitigation:** Acceptable for preferences; the user sees the value from their last local write immediately. External-change notification updates the UI when sync arrives.
- **Risk:** Future settings could proliferate `AppSettings` into a god object. → **Mitigation:** Group related settings with `// MARK:` sections. If it grows past ~10 settings, consider splitting into domain-specific classes.
- **Trade-off:** 1 MB / 1024 key limit on `NSUbiquitousKeyValueStore`. → **Accepted:** App settings are a handful of keys; well within limits.
- **Trade-off:** No offline-first guarantee — if the user has never been online, `NSUbiquitousKeyValueStore` still works locally; values sync when connectivity returns.
