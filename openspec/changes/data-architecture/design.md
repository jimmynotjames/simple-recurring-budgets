## Context

The app is a fresh Xcode project with a placeholder `Item` SwiftData model. No real persistence exists. The PRD and tech design doc specify SwiftData + CloudKit sync, two core entities (Budget, ExpenseItem), and carry-over bookkeeping logic. The feature backlog (T-1 through T-7) defines fields needed now and in the future. CloudKit's additive-only constraint means fields deployed to production can never be removed, making the initial schema consequential.

Current codebase state:
- `Item.swift` — placeholder `@Model` with a single `timestamp` field.
- `simple_recurring_budgetsApp.swift` — `ModelContainer` configured for `Item.self`, no CloudKit.
- Entitlements — CloudKit capability enabled, container identifier already set (`iCloud.com.jimmyho.simple-recurring-budgets`).

## Goals / Non-Goals

**Goals:**
- Define the SwiftData schema (Budget, ExpenseItem, BudgetPeriod/ResetCadence enums) covering core features and select future-ready fields. Features whose schema shape is uncertain (budget icons) are deferred.
- Establish `VersionedSchema` (V1) as a migration baseline.
- Ensure all model design choices are compatible with CloudKit's constraints (entitlements already configured).

**Non-Goals:**
- Implementing UI screens, navigation, or view models.
- Implementing carry-over roll-forward or reset business logic (that belongs in a service layer, built during T-2).
- First-run seeding (F-2.06 — depends on this schema but is a separate change).
- Budget icons — emoji (F-4.03) and photo upload (F-4.04). Visual design is not finalized; schema fields will be added when the feature is designed.

## Decisions

### D1: Split `BudgetPeriod` / `ResetCadence` enums (replaces earlier unified `TimePeriod` decision)

**Choice:** Two separate `String`-backed, `Codable`, `CaseIterable` enums:
- `BudgetPeriod`: `daily`, `weekly`, `biweekly`, `monthly` — also `Comparable` via manual `sortOrder`.
- `ResetCadence`: `weekly`, `biweekly`, `monthly`, `quarterly`, `never` — not `Comparable`; cross-type comparison via `isBroaderThan(_:BudgetPeriod)` method.

**Why:** The value sets diverge: `.quarterly` and `.never` are only meaningful as reset cadences; `.daily` is only meaningful as a budget period. A unified enum would require runtime guards to prevent invalid assignments (e.g. `budget.period = .never`). Split enums give compile-time safety, and each enum's `CaseIterable` returns exactly the valid cases for its context. The minor duplication of shared cases (weekly, biweekly, monthly) is an acceptable trade-off.

**Alternatives considered:**
- *Unified `TimePeriod` enum:* Cleaner when both used the same cases, but broke down with `.quarterly`, `.never`, and the need for `.daily` to be period-only. `CaseIterable` and `Comparable` semantics (especially `.never`) became problematic.

### D2: `String`-backed enums with manual ordering

**Choice:** Both enums use `String` raw values (`"daily"`, `"weekly"`, etc.) for human-readable database/CloudKit records. `BudgetPeriod` has manual `Comparable` via a private `sortOrder` property. `ResetCadence` uses a dedicated `isBroaderThan(_:BudgetPeriod)` method instead of `Comparable`, since `.never` breaks linear ordering semantics.

**Why:** String raw values are inspectable in CloudKit Dashboard and SQLite. Keeping `.never` out of `Comparable` avoids the awkward question of whether `.never < .quarterly` is `true` or `false`.

**Alternatives considered:**
- *Int-backed enums:* Compact but opaque in the database. Inserting new cases requires careful numbering.

### D3: Default reset cadence as a manual mapping on `BudgetPeriod`

**Choice:** A computed property `BudgetPeriod.defaultResetCadence` returning a `ResetCadence` via explicit `switch`: `.daily → .weekly`, `.weekly → .monthly`, `.biweekly → .quarterly`, `.monthly → .quarterly`.

**Why:** Algorithmic derivation doesn't match product intent (e.g. weekly should default to monthly, not biweekly; biweekly should default to quarterly for clean cycle alignment). A hardcoded mapping is trivial to maintain and documents intent.

### D3a: Period-boundary-aligned resets

**Choice:** Scheduled resets fire at the first period boundary after the cadence interval has elapsed since the last reset, never mid-period.

**Why:** Calendar-based cadences (monthly, quarterly) don't divide evenly into non-calendar periods (weekly, biweekly). Resetting mid-period would split carry-over accounting in confusing ways. Period-boundary alignment means the cadence interval is a minimum, and the actual reset may slip by up to one period. For most combinations the variance is negligible; for biweekly + monthly it means 2–3 cycles (28–42 days) instead of exactly 30. The `.quarterly` cadence improves biweekly alignment (roughly 6–7 cycles).

### D4: Signed `amount` for transaction direction (F-6.01)

**Choice:** `ExpenseItem.amount` is a signed `Decimal`. Positive values are expenses (subtract from budget); negative values are "add funds" (increase available balance). Computed helpers `isAddFunds: Bool` and `displayAmount: Decimal` (absolute value) derive presentation from the sign.

**Why:** Every balance calculation reduces to a single sum (`allocation - expenses.sum(\.amount)`) — no conditional branching on a separate boolean. One fewer stored field means one fewer permanent CloudKit column. The UI layer can still present "Add Funds" as a distinct action by negating user input before storage.

**Alternatives considered:**
- *`isAddFunds: Bool`:* Requires every calculation to branch on two fields. Adds a permanent CloudKit column for what the sign already expresses.
- *`direction: String` enum:* Same branching problem, plus an extra enum type for a binary concept.

### D5: `sortOrder: Int` on Budget for user-defined ordering

**Choice:** An `Int` field on Budget, assigned `max(existing) + 1` on creation. Budgets queried with `@Query(sort: \Budget.sortOrder)`.

**Why:** Enables drag-to-reorder in the Budgets list. The field is cheap and avoids a future migration. Without it, ordering is limited to data-driven sorts (name, date).

### D6: `lastModified: Date` on both entities

**Choice:** A `Date` field on Budget and ExpenseItem, initialized to `Date()` and updated on any user-facing mutation.

**Why:** Useful for sync debugging, conflict auditing, and potential future UI ("last edited"). Near-zero cost.

### D7: `VersionedSchema` from V1

**Choice:** Define `SchemaV1` as a `VersionedSchema` and create an empty `SchemaMigrationPlan` referencing it, even though no V2 exists yet.

**Why:** The first migration is always the hardest if there's no baseline. Starting with versioned infrastructure means V2 only needs to add its schema and migration stage — no retrofitting.

**Alternatives considered:**
- *Skip until first migration:* Slightly less upfront code, but creates a discontinuity — V1 data exists without a versioned schema, requiring a bootstrap migration step.

### D9: `isCarryOverEnabled: Bool` on Budget (F-2.07)

**Choice:** A `Bool` field on Budget, defaulting to `true`. When `false`, carry-over is disabled for that budget — the carry-over amount is not computed or displayed. A corresponding `@AppStorage` key `defaultCarryOverEnabled` (default `true`) on the Settings screen controls the initial value for newly created budgets.

**Why:** F-2.07 requires a per-budget toggle. A Bool is the simplest representation. The global default lives in `UserDefaults` (not SwiftData) because it's an app preference, not per-entity data — consistent with how `startOfWeek` (F-5.01) and `colorTheme` (F-4.01) are stored.

**Alternatives considered:**
- *Storing the global default in SwiftData as a singleton "Settings" entity:* Would sync across devices via CloudKit, but adds schema complexity for a single preference. `UserDefaults` with `NSUbiquitousKeyValueStore` could sync it later if needed.

## Risks / Trade-offs

**`Decimal` precision loss in CloudKit** → CloudKit stores `Decimal` as `Double` at the CKRecord level, which can lose precision beyond ~15 significant digits. For personal budget amounts this is effectively zero risk. Mitigation: acceptable for this domain; document the limitation.

**Additive-only CloudKit fields** → Every field deployed to production is permanent. Including future-ready fields (`expenseType`, `isCarryOverEnabled`) now means they'll exist in CloudKit even if those features are never built. Mitigation: these are all optional/defaulted fields with no semantic harm if unused. Fields for uncertain features (budget icons) are intentionally deferred to avoid permanent schema regret.

**`sortOrder` reindexing on reorder** → Moving a budget in the list requires updating `sortOrder` on multiple rows. For a personal app with a handful of budgets, this is trivial. Mitigation: batch updates in a single `modelContext.save()`.

**Carry-over date fields initialized at creation** → `carryOverLastProcessedDate` and `carryOverLastResetDate` are set to `Date()` on Budget creation. If the user creates a budget and doesn't open it for days, the roll-forward service must handle the "no completed periods yet" case gracefully. Mitigation: this is a service-layer concern, not a schema issue — the dates are correct starting state.
