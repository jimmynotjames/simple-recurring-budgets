## 0. Prerequisite: iCloud Key-Value Store Entitlement (manual — Xcode)

> **This task is done manually in Xcode, not by the agent.**
>
> `NSUbiquitousKeyValueStore` requires the **iCloud Key-Value Store** (`com.apple.developer.ubiquity-kvstore-identifier`) entitlement. The project already has an iCloud/CloudKit entitlement in `simple-recurring-budgets/simple_recurring_budgets.entitlements`, but the key-value store service is not enabled yet.
>
> **Steps:**
>
> 1. Open the project in Xcode.
> 2. Select the **simple-recurring-budgets** target.
> 3. Go to **Signing & Capabilities**.
> 4. Find the existing **iCloud** capability section.
> 5. Under **Services**, check the **Key-value storage** checkbox (it should already show **CloudKit** checked).
> 6. Xcode will automatically add `com.apple.developer.ubiquity-kvstore-identifier` to the entitlements file with the value `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`.
> 7. Build to verify — no code changes are needed for this step.
>
> **Why manual?** Entitlement and capability changes are best done through Xcode's UI to ensure the provisioning profile, app ID, and entitlements plist stay in sync. Editing the `.entitlements` plist directly can cause signing mismatches.

---

## 1. Weekday Enum

- [x] 1.1 Create `Weekday.swift` with `Int`-backed enum (cases `sunday = 1` through `saturday = 7`), conforming to `CaseIterable`, `Codable`, `Identifiable`. Include `static func from(calendarFirstWeekday:) -> Weekday?` initializer.
- [x] 1.2 Add unit tests for `Weekday`: raw values, `from(calendarFirstWeekday:)` with valid and invalid inputs, `CaseIterable` ordering.

## 2. KeyValueStore Protocol & AppSettings Class

- [x] 2.1 Create `KeyValueStore.swift` with a `KeyValueStore` protocol abstracting `object(forKey:)`, `set(_:forKey:)`, and `synchronize()`. Add an extension conforming `NSUbiquitousKeyValueStore` to `KeyValueStore`. Add an in-memory `MockKeyValueStore` class for tests.
- [x] 2.2 Create `AppSettings.swift` with `@Observable final class AppSettings`. Define `static let` key constants. Accept `init(store: KeyValueStore = NSUbiquitousKeyValueStore.default)`. On init, check whether each key exists in the store; if absent, use hard-coded defaults (`true` for `defaultCarryOverEnabled`, locale `firstWeekday` for `weekStartDay`). Persist changes via `didSet` + `synchronize()`.
- [x] 2.3 In `AppSettings.init`, register for `NSUbiquitousKeyValueStore.didChangeExternallyNotification`. On receipt, re-read changed keys and update stored properties so `@Observable` triggers UI refresh.
- [x] 2.4 Add unit tests for `AppSettings` using `MockKeyValueStore`: fresh defaults produce correct values, persisted values are read on init, setting a property persists to the store, invalid `weekStartDay` falls back to locale default, external-change notification updates properties.

## 3. Environment Injection

- [x] 3.1 In `simple_recurring_budgetsApp.swift`, add `@State var settings = AppSettings()` and inject into the view hierarchy via `.environment(settings)`.

## 4. Budget Init Wiring

- [x] 4.1 Remove the `TODO(F-2.07)` comment in `Budget.swift`. Verify that `Budget.init` already accepts `isCarryOverEnabled` with a default of `true` (no code change needed to the init itself — callers will pass the setting value at creation time).

## 5. Docs Updates

- [x] 5.1 Update `docs/tech-design-doc.md`: section 8 future considerations table (F-5.01 and F-4.01–02) to reflect `NSUbiquitousKeyValueStore` instead of `UserDefaults` for app settings; add a note about iCloud key-value store usage.
- [x] 5.2 Update `docs/product-features-planning.md`: F-2.07 and F-5.01 descriptions to note that these settings sync across the user's iCloud-connected devices.
