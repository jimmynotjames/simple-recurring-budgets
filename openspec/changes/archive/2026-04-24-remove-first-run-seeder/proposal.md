## Why

The `FirstRunSeeder` (added under the still-pending `add-first-run-seeder` change) inserts a placeholder `"Food"` Budget on first launch so the Budgets screen is not empty. Industry and HIG practice has moved away from unlabeled silent-seed rows in money-adjacent apps: users often cannot distinguish a fake seed from their own data, the forward-seal / two-gate machinery exists only to protect a UX decision we are now backing out of, and the eventual Budgets screen (F-2.01) will ship its own empty state with a primary "Create a budget" CTA that serves the first-launch moment more honestly. Removing the seeder now — before F-2.01 lands and before `add-first-run-seeder` is archived into main specs — lets us delete code, tests, analytics, KV state, and docs in a single coherent step rather than adding contortions on top.

## What Changes

- **BREAKING (user-visible on first launch):** First launch on a brand-new install with an empty store no longer auto-inserts a `"Food"` Budget. The Budgets screen (placeholder today, real screen in F-2.01) will show its empty state.
- **Delete `App/FirstRunSeeder.swift`** and the associated test file `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift`. No replacement namespace is introduced — "no seed" is not a service.
- **Remove the seeder wiring** from `simple_recurring_budgetsApp.swift`: drop the `.task { ... FirstRunSeeder.seedIfNeeded(...) ... }` block and the three `firstRun.*` analytics branches it feeds. Keep the single `AnalyticsEvent.appLaunched` track (moved so it still fires exactly once per launch).
- **Retire the `"seededV1"` iCloud KV key.** No migration or cleanup write is performed: the key lives in `NSUbiquitousKeyValueStore` and is harmless if left behind on existing installs (it is simply never read again). Document this "orphaned but harmless" status in the tech design.
- **Remove the `firstRun.seeded` / `firstRun.skipped` / `firstRun.error` analytics event constants** from `Logging/AnalyticsClient.swift` and their assertions in `simple-recurring-budgetsTests/Logging/AnalyticsClientTests.swift`. These events only existed to observe the seeder and have no other callers.
- **Supersede the pending `openspec/changes/add-first-run-seeder/` change** by deleting its directory. It was never archived into `openspec/specs/`, so the `first-run-seed` capability never formally existed in the main spec set and there is no main-spec delta to emit here. The deletion is captured as an explicit task so the audit trail is not silent.
- **No changes** to `Budget`, `AppSettings`, `KeyValueStore`, `BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`, or `SchemaV1`. No CloudKit schema changes. No new dependencies.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

_(none — no existing spec in `openspec/specs/` has requirements about first-run seeding. The `first-run-seed` capability was defined only inside the unarchived `add-first-run-seeder` change; deleting that change directory is a file-level cleanup, not a spec-level modification.)_

## Impact

- **Deleted code**:
  - `simple-recurring-budgets/App/FirstRunSeeder.swift`
  - `simple-recurring-budgetsTests/App/FirstRunSeederTests.swift`
- **Modified code**:
  - `simple-recurring-budgets/App/simple_recurring_budgetsApp.swift` — remove `.task` seeding block; collapse to a minimal `.task { analytics.track(AnalyticsEvent.appLaunched) }` (or equivalent single-line wiring). Drop `import SwiftData`-scoped references no longer needed (`NSUbiquitousKeyValueStore.default`, `FirstRunSeeder`).
  - `simple-recurring-budgets/Logging/AnalyticsClient.swift` — remove the three `firstRun.*` constants.
  - `simple-recurring-budgetsTests/Logging/AnalyticsClientTests.swift` — remove the three `firstRun.*` event-name assertions (only).
- **Deleted OpenSpec**:
  - `openspec/changes/add-first-run-seeder/` (entire directory).
- **Docs to update**:
  - `docs/tech-design-doc.md` — remove §4.6 ("First-Run Bootstrap (FirstRunSeeder)"), §5.5 ("Bootstrap"), and the `"seededV1"` row in the §4.5 KV key table. Add a one-line note (in §4.5 or a new changelog entry) recording that `"seededV1"` is an orphaned key on upgraded installs and must not be reused. Bump the version-history table.
  - `docs/product-features-planning.md` — rewrite F-2.06 from "First-run seed and empty state" to "First-run empty state" (or similar): remove the seed acceptance criteria; keep/add an empty-state expectation that aligns with F-2.01. Alternative (to be settled in design.md): mark F-2.06 `Status: Cancelled / Superseded` and fold the empty-state responsibility into F-2.01's acceptance criteria.
  - `docs/main-prd.md` — no changes (no references to the seed).
- **CloudKit**: no schema change. Existing installs whose `"seededV1"` flag already synced continue to sync it harmlessly; the app no longer reads it.
- **Test signal**: total test count drops by the FirstRunSeederTests suite plus three event-name assertions. No other tests exercise the seeder.

## Doc alignment

- **Aligned** with `docs/main-prd.md` — PRD does not require a seed Budget; the glossary and constraints are unchanged.
- **Conflict with `docs/product-features-planning.md` §F-2.06** — the feature as written mandates seeding a `"Food"` Budget. Resolution: **update the doc** (rewrite F-2.06 as empty-state-only, or mark it superseded by F-2.01). Exact wording decided in design.md and applied as a task.
- **Conflict with `docs/tech-design-doc.md` §§4.5 / 4.6 / 5.5** — these sections document `FirstRunSeeder` and `"seededV1"` as living components. Resolution: **update the doc** (delete §4.6 and §5.5; trim the §4.5 KV key table). Captured as tasks.
- **Doc updates required after implementation**:
  - `docs/product-features-planning.md` (F-2.06 rewrite)
  - `docs/tech-design-doc.md` (§4.5 table trim, §4.6 and §5.5 removal, version-history bump)
