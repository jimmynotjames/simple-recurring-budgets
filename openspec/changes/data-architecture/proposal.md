## Why

The app has no data model yet — only Xcode's placeholder `Item` model. Every feature from T-2 onward (budget CRUD, expense tracking, carry-over bookkeeping) is blocked until the persistence layer exists. **CloudKit** record types are **additive-only** once deployed: new fields can be added later, but **removed fields are not really gone** from the synced schema—so shipping a deliberate initial shape (including optional, defaulted future-ready fields for T-4/T-6, minus some deferred parts) limits long-lived clutter and avoids painting ourselves into a corner. **`VersionedSchema`** addresses a different concern: a baseline for **SwiftData** migration steps when the model must evolve in ways that are not a simple additive column (transforms, non-trivial renames, staged moves between versions).

## What Changes

- **Replace** the template `Item` model with two `@Model` entities: `Budget` and `ExpenseItem`, linked by a one-to-many relationship (cascade delete).
- **Introduce** two `String`-backed enums: `BudgetPeriod` (`daily`, `weekly`, `biweekly`, `monthly`) with `Comparable` ordering for `Budget.period`, and `ResetCadence` (`weekly`, `biweekly`, `monthly`, `quarterly`, `never`) for `Budget.resetCadence`. Split because the value sets diverge — `.quarterly` and `.never` are only valid as reset cadences, `.daily` is only valid as a budget period. Cross-type comparison via `ResetCadence.isBroaderThan(_:BudgetPeriod)`.
- **Define** period-boundary-aligned reset rule: scheduled resets fire at the first period boundary after the cadence interval has elapsed, never mid-period.
- **Include future-ready fields** on the models: `expenseType: String?` (F-6.02), `sortOrder: Int` (user-defined budget ordering), `lastModified: Date` (audit/sync).
- **Use signed `amount`** on ExpenseItem: positive = expense, negative = add funds (F-6.01). No separate `isAddFunds` field needed; computed helpers derive direction from the sign.
- **Add** `isCarryOverEnabled: Bool` on Budget (F-2.07) — per-budget toggle controlling whether carry-over is active. Defaults to `true`. A corresponding global default (`defaultCarryOverEnabled`) lives in `UserDefaults` / `@AppStorage`.
- **Set up** `VersionedSchema` (V1) and `SchemaMigrationPlan` infrastructure so the first real migration has a baseline.
- **Remove** `Item.swift` and all references to it.

## Capabilities

### New Capabilities

- `data-models`: SwiftData `@Model` definitions for `Budget` and `ExpenseItem`, including all fields, relationships, defaults, and the `BudgetPeriod` / `ResetCadence` enums.
- `schema-versioning`: `VersionedSchema` (V1) and `SchemaMigrationPlan` setup for future migration support.

### Modified Capabilities

(none — no existing specs)

## Deferred features (not in this schema)

The following features are **not** represented in the initial schema. Their fields will be added when the features are designed and prioritized:

- **F-4.03 / F-4.04: Budget icons** (emoji and photo upload) — Visual design for icons is not yet finalized; schema shape depends on that decision (including any binary asset field and CloudKit asset considerations).

**F-6.01 (Adding funds)** is supported via signed `amount` on ExpenseItem — no extra field required.

## Pre-conditions

- CloudKit entitlements already configured (`iCloud.com.jimmyho.simple-recurring-budgets`).

## Impact

- **Code**: `Item.swift` deleted; `simple_recurring_budgetsApp.swift` and `ContentView.swift` updated to reference new models. New files for `Budget`, `ExpenseItem`, `BudgetPeriod`, `ResetCadence`, and schema versioning.
- **Tests**: Existing placeholder test references to `Item` must be updated. New model tests use in-memory `ModelContainer`.
