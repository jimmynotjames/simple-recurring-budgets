## Why

Several features require app-wide settings that persist across launches and are readable from both views and business logic: the default carry-over toggle for new budgets (F-2.07) and the configurable start-of-week day (F-5.01). These settings live in `NSUbiquitousKeyValueStore`, not SwiftData, because they are lightweight preferences — not user data that belongs in the relational store. Using `NSUbiquitousKeyValueStore` instead of `UserDefaults` means settings sync automatically across the user's devices via iCloud (same Apple ID), giving a consistent experience without additional infrastructure. A centralized, testable persistence layer for these settings is needed before any Settings UI can be built.

## What Changes

- Introduce a `Weekday` enum (`Int`-backed, 1=Sunday…7=Saturday, matching `Calendar.firstWeekday`) for type-safe week-start configuration.
- Introduce an `@Observable` `AppSettings` class that owns all `NSUbiquitousKeyValueStore`-backed settings as stored properties with `didSet` persistence and external-change observation. Initial settings:
  - `defaultCarryOverEnabled` (`Bool`, default `true`) — F-2.07
  - `weekStartDay` (`Weekday`, default from `Calendar.current.firstWeekday`) — F-5.01
- Inject `AppSettings` into the SwiftUI environment from the app entry point so views, view models, and budget-creation logic can all access it.
- Wire `Budget.init` to accept an `isCarryOverEnabled` parameter sourced from `AppSettings.defaultCarryOverEnabled` at creation time (resolves existing TODO in `Budget.swift`).

## Capabilities

### New Capabilities

- `app-settings`: Centralized `NSUbiquitousKeyValueStore`-backed persistence layer for app-wide settings (synced across the user's iCloud devices), including the `AppSettings` observable class, `Weekday` enum, and environment injection.

### Modified Capabilities

- `data-models`: The carry-over toggle requirement already references `@AppStorage defaultCarryOverEnabled`; this change provides the concrete implementation that `Budget.init` reads from.

## Impact

- **New files:** `AppSettings.swift`, `Weekday.swift`
- **Modified files:** `simple_recurring_budgetsApp.swift` (environment injection), `Budget.swift` (consume setting at init)
- **Entitlements:** iCloud key-value store entitlement (already required for CloudKit; `NSUbiquitousKeyValueStore` uses the same iCloud container).
- **Tests:** New unit tests for `AppSettings` read/write/defaults, external-change notification handling, and `Weekday` enum; tests use a mock or in-memory key-value store protocol for isolation.
- **No new dependencies.** Uses Foundation `NSUbiquitousKeyValueStore` only.
