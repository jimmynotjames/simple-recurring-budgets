## Why

F-2.06 requires that on first launch with an empty data store, the Budgets screen is not empty — a single `"Food"` Budget must be seeded so the user lands on something tangible. The seed must run exactly once per iCloud account (not once per device, not once per install), must never run again after the user has intentionally emptied the store, and must be safe against the common "reinstall on a synced device" case where CloudKit-backed SwiftData has not yet replicated when the app first starts. Nothing in the codebase currently performs this bootstrap; `ContentView` shows a placeholder root and `simple_recurring_budgetsApp` wires only the container and environment. We need a narrow, testable bootstrapper owning this contract.

## What Changes

- **New `FirstRunSeeder`** in `App/` (stateless `enum` namespace, matching the existing `BudgetLifecycleService` / `BudgetCalculator` pattern) — provides an async `seedIfNeeded(context:store:isCarryOverEnabled:now:)` entry point that runs the two-gate seed decision and the single insert.
- **Two-gate seeding** — seed only when BOTH (a) the iCloud key-value store has no value for the `"seededV1"` key AND (b) a `FetchDescriptor<Budget>` `fetchCount` returns `0`. Either gate alone is insufficient: the KV flag handles same-account reinstalls across devices; the store count handles the CloudKit-synced-before-KV race on a device that already has data.
- **Flag write ordering** — write `"seededV1" = true` to the iCloud key-value store *after* a successful `context.save()`. A crash between insert and flag write causes at worst one duplicate seed on next launch (recoverable by the user), which is strictly better than writing the flag first and permanently suppressing seeding if the save fails.
- **Seed content matches F-2.06** — `Budget` with `name: "Food"`, `period: .daily`, `allocation: 25`, `resetCadence: .weekly` (explicit, even though it equals `BudgetPeriod.daily.defaultResetCadence`), `currencyCode` defaulted via `Budget.init` (locale → USD), `sortOrder` from `Budget.nextSortOrder(for:)`, and `isCarryOverEnabled` sourced from `AppSettings.defaultCarryOverEnabled` — the same path a user-created budget would take on the Add/Edit Budget screen (F-2.03).
- **Integration point** — `ContentView` attaches a `.task` modifier on the Budgets root that calls the seeder with the environment `ModelContext`, `NSUbiquitousKeyValueStore.default`, and `AppSettings.defaultCarryOverEnabled`. No changes to `simple_recurring_budgetsApp` or the `WindowGroup`; the task lives where the model context is in scope.
- **`KeyValueStore` protocol extension** — add a `set(_ value: Any, forKey:)`-style accessor only if needed; the existing `set(_ value: Bool, forKey:)` already covers the `"seededV1"` write, so no protocol changes are expected. The existing `MockKeyValueStore` is reused for tests.
- **Errors are swallowed with `try?`** — consistent with the rest of the eager write paths in the app. A failed seed leaves the Budgets screen in its normal empty state; the user can create a budget manually, and a future launch will re-attempt (both gates will still be open).
- **No schema changes, no new app-settings keys beyond `"seededV1"`, no ViewModel changes** outside of the one `.task` wiring.

## Capabilities

### New Capabilities

- `first-run-seed`: One-time, per-iCloud-account bootstrap of a seed `Budget` when the user first launches the app on an empty store. Owns the two-gate decision (iCloud KV flag + store emptiness check), the single insert/save, and the flag write-back.

### Modified Capabilities

_(none — no existing spec's requirements change. `app-settings` gains no new properties; `data-models` gains no new fields; `budget-lifecycle` is not involved in this flow.)_

## Impact

- **New files in `App/`**: `FirstRunSeeder.swift` (service + any private helpers).
- **Modified files**:
  - `Views/ContentView.swift` — add `.task { await FirstRunSeeder.seedIfNeeded(...) }` on the Budgets root; read `@Environment(\.modelContext)` and `@Environment(AppSettings.self)`.
- **New test file**: `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift` — uses the existing in-memory `ModelContainer` helper and `MockKeyValueStore` to assert each of the gate combinations, seed content, flag write ordering, and post-save idempotency. Covers:
  - Gate A closed (flag already set) → no seed, no save.
  - Gate B closed (store non-empty, flag unset) → no seed, but flag is written (forward-seals the seed from future accidental reseed).
  - Both gates open → exactly one seed with the specified field values; flag set; second call does nothing.
  - Save failure path → flag remains unset so a future launch retries (verified via a model-context test double or by inspecting flag state after an induced failure where feasible).
- **No changes** to `Budget`, `ExpenseItem`, `SchemaV1`, `BudgetCalculator`, `PeriodCalculator`, or `BudgetLifecycleService`.
- **No changes** to `AppSettings` public API; the seeder reads `defaultCarryOverEnabled` through `AppSettings` but does not set it.
- **No new third-party dependencies.** Apple-only.
- **CloudKit**: the `"seededV1"` key lives in `NSUbiquitousKeyValueStore`, which shares the app's existing iCloud container entitlement; no CloudKit schema changes. The seeded `Budget` CKRecord is created by SwiftData on the first push, same as any user-created budget.

## Doc alignment

- **Aligned** with `docs/main-prd.md` — F-2.06 acceptance criteria are respected verbatim (name `"Food"`, daily, allocation 25, weekly reset cadence, locale-default currency, per-budget fields consistent with F-2.03, runs once, no reseed on manual delete).
- **Aligned** with `docs/product-features-planning.md` §F-2.06 and §F-2.03 — the seeder uses the same field defaults as the Add/Edit Budget screen (currency from locale, `isCarryOverEnabled` from `AppSettings.defaultCarryOverEnabled`, `sortOrder` via `Budget.nextSortOrder(for:)`).
- **Aligned** with `docs/tech-design-doc.md` §4.5 — `"seededV1"` is exactly the kind of small, app-wide, iCloud-synced preference that belongs in `NSUbiquitousKeyValueStore`. Respects the "no `register(defaults:)` equivalent" rule by checking key existence explicitly via `object(forKey:) == nil`.
- **Aligned** with `docs/tech-design-doc.md` §5.3 — `FirstRunSeeder` is a pure-ish namespace service with all dependencies (`ModelContext`, `KeyValueStore`, `isCarryOverEnabled`, `now`) injected, keeping it testable without SwiftUI or a real iCloud store.
- **Doc updates needed after implementation**:
  - `docs/tech-design-doc.md` — short addition (likely in §4.5 or a new §5.5 "Bootstrap") documenting `FirstRunSeeder` as the owner of the `"seededV1"` key, the two-gate decision, and the `.task` wiring in `ContentView`. Add `"seededV1"` to the list of iCloud KV keys used by the app.
  - `docs/product-features-planning.md` — no changes (F-2.06 acceptance criteria already match; this change implements them rather than altering them).
  - `docs/main-prd.md` — no changes.
