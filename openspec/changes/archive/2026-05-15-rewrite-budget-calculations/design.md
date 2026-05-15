## Context

The current carry-over algorithm is `BudgetCalculator.rollCarryOver(...)`, a boundary-only roll that mutates `Budget.carryOverAmount` and advances `Budget.carryOverLastProcessedDate` whenever a period boundary is crossed. It is invoked from `BudgetLifecycleService.refreshAndSave(_:settings:context:)`, which the views call from `.task(id:)` and `.onChange(of: scenePhase)`. The result is a chip that does **not** refresh in response to mid-period expense edits — the bug that motivates this change.

The algorithm is also entangled with two features that are no longer wanted:

- **Reset Cadences** — paused 2026-04-28; the picker is hidden but `Budget.resetCadence: String` still persists `"never"` and `BudgetCalculator.checkScheduledReset(...)` is a runtime no-op. The briefing (§5.4) removes the feature permanently.
- **`AppSettings.weekStartDay` as a math-time fallback** for weekly/biweekly budgets — per-budget anchoring via `startDate` is now the desired model (briefing §2.4 / F-5.01 conflict resolution).

Greenfield context (briefing §1): the app has not shipped to the App Store, no production rows exist. SwiftData schema can be reshaped freely — `SchemaV1.swift` and `BudgetMigrationPlan.swift` are updated in place, and no `SchemaV2` is introduced.

The algorithm design itself is fully specified in [`docs/budget-calculations-rewrite-algorithm.md`](../../../docs/budget-calculations-rewrite-algorithm.md) (referenced below as "algorithm doc §A.x"). This design document covers only the migration-scoping choices and the integration seams — it does not re-derive the math.

## Goals / Non-Goals

**Goals:**

1. Replace `rollCarryOver` + `checkScheduledReset` with a pure read entry point `BudgetCalculator.snapshot(budget:expenses:now:calendar:) -> BudgetSnapshot` (algorithm doc §A.4) built on `walkCarryOver`, `allocationInEffect`, `isActive`, and `currentPeriodSpillover` (algorithm doc §A.5).
2. Reshape the SwiftData schema (algorithm doc §A.2): drop the four legacy fields from `Budget`, add `startDate` / `endDate` / `lastResetDate` / `allocationChangesStorage` / `lifecycleEventsStorage`, add two new entities (`AllocationChange`, `LifecycleEvent`), add the `BudgetPeriod.specificDates` case, delete `ResetCadence`.
3. Fix the mid-period stale-chip bug at the view layer by adopting a single project-wide refresh signal: every user-initiated write that affects budget math bumps `Budget.lastModified` in the same `ModelContext.save()`; views observe `.onChange(of: budget.lastModified)`.
4. Keep `BudgetLifecycleService` as a compatibility seam — same public `refreshAndSave` signature and same `BudgetLifecycleResult` shape so view sites need zero changes for the read path. Internally, map `BudgetSnapshot` to the legacy result.
5. Add three new write-path service methods (`applyAllocationEdit`, `resetCarryOver`, `resetBudget`) so view sites stop reaching directly into `Budget` for math-affecting writes.
6. Preserve `AppSettings.weekStartDay`'s existing behavior for weekly/biweekly budgets at creation time: `AddEditBudgetViewModel.save()` (Add mode) seeds `startDate` from `weekStartDay` so the existing user preference still anchors the budget cycle, even though no UI input is shipping.
7. Keep the four existing recurring period types (`.daily`, `.weekly`, `.biweekly`, `.monthly`) behaviorally equivalent at the user-facing level. The only acceptable user-visible changes are the two ride-along behaviors (mid-period refresh and asymmetric live coupling) — these are intrinsic to the algorithm rewrite.

**Non-Goals (deferred to future changes):**

- **Pause / Resume UI** (toolbar action, paused chip overlay, "Paused since X" caption, `pauseBudget` / `resumeBudget` service methods). Algorithm handles `LifecycleEvent` rows correctly; no UI produces them in this change.
- **Start Date / End Date input fields** on the Add/Edit Budget screen. Defaults wire in code; no UI input controls.
- **Specific Dates period type chip** on the Add/Edit Budget screen. The enum case exists; the chip group continues to render only the four recurring types.
- **Pre-start / post-end chip overlays** ("Starts on X", "Ended on X"). Algorithm returns `.preStart` / `.postEnd` correctly; no UI renders them.
- **Add/Edit Expense date-bounds picker.** Picker stays unconstrained except for whatever it does today.
- **F-6.01 Add Funds toggle.** Not in this change.
- **New analytics events / properties** (`budget_paused`, `budget_resumed`, the new `budget_edited` property flags). Not shipping.
- **Deletion of `BudgetLifecycleService`** (algorithm doc §A.8 Option 1). Explicitly overridden — service stays as an adapter; deletion is a future change.
- **Chip copy changes** for surplus/deficit, overspend, etc. Current copy stays.
- **`docs/ux-design-brief.md` and `docs/analytics-spec.md` updates** for the deferred UI. Not in this change.
- **Screen-level openspec specs** (`add-edit-budget-screen`, `budgets-screen`, `budget-detail-screen`, `add-edit-expense-screen`). No new scenarios added; only stale boundary-only `rollCarryOver` phrases and PAUSED Reset Cadences notes are removed.
- **Schema versioning machinery** (`SchemaV2`, `VersionedSchema`, `SchemaMigrationPlan` stages). Greenfield — update `SchemaV1.swift` and `BudgetMigrationPlan.swift` in place; do not delete them.

## Decisions

### 1. Keep `BudgetLifecycleService` as a compatibility adapter

**Decision.** Override algorithm doc §A.8 Option 1 (which recommended deleting the service). Keep `BudgetLifecycleService.refreshAndSave(_:settings:context:) -> BudgetLifecycleResult` with its existing signature and return type. Internally rewrite it as a pure read that calls `BudgetCalculator.snapshot(...)` and maps the result.

**Why.** Every view in the app currently consumes `BudgetLifecycleResult { remaining, carryOverAmount, periodStart, periodEnd }` — `BudgetsView`, `BudgetDetailView`, `CarryOverChip`, and any chip-observing view-model. Replacing the service would require touching all of those sites and adding a separate compatibility layer anyway. The adapter pattern lands the new algorithm without expanding the change's view-layer surface area. Service deletion is its own future change.

**Mapping (mechanical):**

| Legacy field | Snapshot source |
| --- | --- |
| `BudgetLifecycleResult.remaining` | `snapshot.remaining` |
| `BudgetLifecycleResult.carryOverAmount` | `snapshot.carryOver ?? 0` (defensive — `.specificDates` cannot reach this seam in this migration since no UI creates one) |
| `BudgetLifecycleResult.periodStart` | `snapshot.effectivePeriodStart` |
| `BudgetLifecycleResult.periodEnd` | `snapshot.effectivePeriodEnd` |

`snapshot.lifecycleState` and `snapshot.effectiveAllocation` are NOT exposed through the legacy result. They will be plumbed when the lifecycle UI features ship.

**Alternative considered.** Deleting the service and exposing `BudgetCalculator.snapshot(...)` directly to views via a `@MainActor` extension. Rejected because it widens the view-layer change set without delivering user-visible value in this migration — the algorithm rewrite is independently valuable and the seam keeps the diff bounded.

**Naming note.** The name `refreshAndSave` is a misnomer after this change (the walker is live; there is nothing to save). Renaming is deferred — a future change will rename the method, delete the service, or both.

### 2. Single refresh signal: `Budget.lastModified` at every math-affecting write site

**Decision.** Project-wide rule (algorithm doc §A.6 preamble + §A.2.7): every user-initiated write that affects budget math bumps `Budget.lastModified = now` in the same `ModelContext.save()`. Views observe `.onChange(of: budget.lastModified)` to refresh the chip, alongside the existing `.task(id: budget.persistentModelID)` and `.onChange(of: scenePhase)`.

**Write sites that bump `Budget.lastModified`:**

- `ExpenseItem` add, edit, delete (`ExpenseItem.budget?.lastModified = now` in the same save).
- `Budget` allocation edit (via `applyAllocationEdit`).
- Manual Reset Carry-Over (via `resetCarryOver`).
- Reset Budget (via `resetBudget`).
- Backdated expense edits — folded in automatically because all expense writes go through the same path.
- Future write sites (pause, resume, start/end date edits) will follow the same rule.

**Why.** The mid-period stale-chip bug is a refresh-trigger bug, not a math bug. Today, view code relies on `.onChange(of: budget.expenseItems.count)`, which catches Add and Delete but **not** Edit (count is unchanged). After this change, all three cases are covered uniformly by `lastModified` because every write bumps the timestamp. This is a more reliable single signal than trying to enumerate every observable property.

**Coexistence with `.onChange(of: budget.expenseItems.count)`.** It is harmless to leave both observers — `lastModified` fires for every case, and the count-based observer fires for Add/Delete. The migration optionally removes the redundant count observer; doing so is not required.

**Alternative considered.** Driving refresh from a `Combine`/`AsyncStream` publisher on the SwiftData context. Rejected as out of proportion to the bug — `.onChange(of: lastModified)` is one line per view, deterministic, and matches the existing pattern.

### 3. Per-period-type `startDate` defaults in `AddEditBudgetViewModel.save()` (Add mode)

**Decision.** Compute `startDate` per period type at Add time (algorithm doc §A.6.1 storage convention; briefing F-2.03 pre-population rule applied in code since the UI has no Start Date field yet):

- **Daily:** `startDate = calendar.startOfDay(for: createdAt)`.
- **Weekly / biweekly:** `startDate = most recent AppSettings.weekStartDay-aligned date at or before startOfDay(createdAt)`.
- **Monthly:** `startDate = start of the calendar month containing createdAt`.
- **Specific Dates:** N/A in this migration (chip group does not expose `.specificDates`).

Insert one initial `AllocationChange(effectiveFrom: startDate, amount: enteredAllocation)` in the same `context.save()`.

**Why.** Without this, every new budget would anchor its weekly/biweekly cycle to `createdAt.weekday`, silently ignoring the user's `AppSettings.weekStartDay` preference (F-5.01). The briefing's §2.4 pre-population rules are the contract the new algorithm honors; this migration applies those rules in code as the proxy for the not-yet-shipped UI input.

All four computed values are start-of-day-aligned, so `effectiveFrom = startDate` matches algorithm doc §A.6.1's storage convention exactly. The algorithm's defensive `?? sorted.first?.amount` fallback in `allocationInEffect` is never triggered in the normal flow.

**Alternative considered.** Defaulting `startDate = createdAt` and ignoring period-type-specific anchoring. Rejected because it silently changes weekly/biweekly behavior for any user who currently relies on `AppSettings.weekStartDay` to align their cycles — the migration must preserve user-facing behavior for the four recurring types.

### 4. `Budget` field optionality — CloudKit pattern

**Decision.** Per algorithm doc §A.2's `[!IMPORTANT]` callout: `startDate`, `endDate`, `lastResetDate`, `allocationChangesStorage`, and `lifecycleEventsStorage` are all stored as `Optional`. Non-optional computed accessors `allocationChanges` and `lifecycleEvents` wrap the storage with `?? []` for read sites.

**Why.** CloudKit-synced SwiftData relationships must be optional. The computed accessors hide that constraint from the algorithm and view-model code, which always sees `[AllocationChange]` and `[LifecycleEvent]`.

**Read-time `startDate` fallback.** If a malformed sync record arrives with `startDate = nil`, the algorithm falls back to `createdAt` (algorithm doc §A.4.1 step 1). The UI requires `startDate` at save time (proxied here by the Add-mode computation), so this is a safety net, not a normal-flow state.

### 5. `RecurringBudgetPeriod` wrapper for `PeriodCalculator`

**Decision.** Introduce a `RecurringBudgetPeriod` enum (algorithm doc §A.5.1) covering `.daily / .weekly / .biweekly / .monthly`. `PeriodCalculator`'s public surface accepts `RecurringBudgetPeriod`, not `BudgetPeriod`. The `.specificDates` case has its own branch in `BudgetCalculator.snapshot(...)` (algorithm doc §A.4.2) and never reaches `PeriodCalculator`.

**Why.** Compile-time enforcement that `.specificDates` cannot accidentally drive recurring period math. `PeriodCalculator` itself stays untouched for the four recurring types.

**Alternative considered.** A runtime `precondition(period != .specificDates)` in `PeriodCalculator`. Rejected — a compile-time guard is strictly stronger and free.

### 6. `LifecycleEvent.kind` typed as `LifecycleEventKind` enum directly

**Decision.** Per algorithm doc §A.2.3: `LifecycleEvent.kind: LifecycleEventKind` where `LifecycleEventKind` is `String, Codable`. SwiftData serializes `String, Codable` enums automatically. Do **not** use a `String` raw field with a separate computed accessor.

**Why.** Cleaner read sites (`event.kind == .pause`) and one fewer accessor to maintain. SwiftData's `String, Codable` support has been stable since the framework's release.

### 7. Compatibility-defensive coding limited to documented seams

**Decision.** Two defensive fallbacks survive into production code:

- `snapshot.carryOver ?? 0` in the `BudgetLifecycleResult.carryOverAmount` mapping (handles the theoretical `.specificDates` case at the seam — not reachable in this migration).
- `startDate ?? createdAt` in the snapshot read path (handles malformed sync records).

Everything else (e.g., "what if `allocationChanges` is empty when computing `allocationInEffect`?") is handled by algorithm-internal contracts (algorithm doc §A.5.2's `?? sorted.first?.amount`) and is never invoked in normal flow because Add-mode always inserts the initial row.

**Why.** Each defensive line is justified by a CloudKit-divergence or future-UI-not-yet-shipped scenario. Adding more defensive coding than that would be noise.

### 8. Schema versioning — update in place, no `SchemaV2`

**Decision.** Per briefing §1: update `SchemaV1.swift` and `BudgetMigrationPlan.swift` to reflect the new shape. Do not introduce `SchemaV2`, `VersionedSchema`, or `SchemaMigrationPlan` stages. Do not delete `SchemaV1.swift` or `BudgetMigrationPlan.swift`.

**Why.** Greenfield app, no production users. Migration ceremony has zero value here and would obscure the schema's actual shape. The `SchemaV1.swift` file stays so any future schema bump has a starting point.

### 9. Test plan — algorithm doc §A.10 is the contract

**Decision.** Adopt algorithm doc §A.10's test plan wholesale: unit tests on `BudgetCalculator.snapshot(...)` (per lifecycle state), helper tests (`allocationInEffect`, `currentPeriodSpillover`, `isActive`), walker tests (`walkCarryOver`), SwiftData round-trip integration tests, and CloudKit-divergence simulation tests. The **★** marks in §A.10 flag the high-risk edge cases that must not be skipped.

Add adapter-mapping tests for `BudgetLifecycleService` covering every lifecycle state the legacy result exposes.

Delete every test for `rollCarryOver`, `checkScheduledReset`, `defaultResetCadence`, and any cadence-related lifecycle scenarios.

Do not add UI tests for the deferred features (Pause/Resume, Start/End Date inputs, Specific Dates creation flows, lifecycle chip overlays). Those ship with the respective future changes.

### 10. View-layer change set is strictly minimal

**Decision.** Exactly five view-side change classes (migration prompt §3.4):

1. `AddEditBudgetViewModel.save()` (Add mode) — compute per-period-type `startDate`; insert initial `AllocationChange` row.
2. `AddEditBudgetViewModel.save()` (Edit mode) — route allocation changes through `applyAllocationEdit`.
3. Every `ExpenseItem` write site (Add, Edit, Delete) — bump `budget.lastModified = now` in the same `context.save()`. View observers add `.onChange(of: budget.lastModified)`.
4. Reset Budget call site — call `BudgetLifecycleService.resetBudget(...)`.
5. Reset Carry-Over call site — call `BudgetLifecycleService.resetCarryOver(...)`.

Everything else in the view layer is unchanged.

**Why.** Behavioral equivalence at the user-facing-feature level (algorithm rewrite excluded) means no new fields, toolbar actions, screens, overlays, copy, or pickers. Each future UI change reopens the view layer on its own terms.

## Risks / Trade-offs

- **Risk: An out-of-scope UI tweak slips in "while we're already in there."** → Mitigation: the migration prompt §4 has an explicit "out of scope" list and the test for whether a doc update is in scope is "does the user see anything new in the app?" Tasks.md mirrors the in-scope list; verify before archive.
- **Risk: A view observer is missed, so the chip still doesn't refresh for a specific write.** → Mitigation: the single-signal rule (`lastModified` at every write site, observed in every chip view) is enforced in code review. Adapter-mapping tests cover the read path; SwiftData round-trip tests cover that `lastModified` is written.
- **Risk: `AppSettings.weekStartDay` seed for weekly/biweekly budgets falls out of sync with the briefing's §2.4 rule if the user has the simulator in a non-default state during testing.** → Mitigation: snapshot/helper tests in §A.10 cover every period-type `startDate` derivation; the Add-mode path has unit tests for each branch.
- **Risk: `BudgetLifecycleResult.carryOverAmount ← snapshot.carryOver ?? 0` defensive `?? 0` silently swallows a real `.specificDates` budget that somehow reaches this seam.** → Mitigation: no UI in this migration creates `.specificDates`; the case is dead in production. When the Specific Dates UI ships, the future change must remove the `?? 0` and use a typed result instead.
- **Risk: Schema reshape requires wiping the simulator for any device with old data.** → Mitigation: documented in the proposal Impact section and in tasks.md; greenfield context makes this acceptable.
- **Trade-off: Keeping `BudgetLifecycleService` increases lines of code that will be deleted later.** → Accepted. The adapter is small (one read method + three write methods); the alternative (touch every view site twice — once now, once when the service is eventually deleted) is more total churn.
- **Trade-off: The `.specificDates` enum case exists in code but no UI exposes it.** → Accepted. The algorithm must handle the case correctly because future changes will add the UI; testing the algorithm now is cheaper than wiring a flag.

## Migration Plan

This is a greenfield app (briefing §1) — there is no rollout strategy, no feature flag, and no rollback path beyond reverting the commit. Specifically:

1. Land the schema reshape and the algorithm rewrite in the same change. After merge, every developer must wipe the simulator (or accept that existing simulator data will not load) — there is no SwiftData migration.
2. The build/test loop per `AGENTS.md`: `make format` → `make lint-fix` → `make build` → `make test`.
3. No production users exist, so no App Store risk.
4. CloudKit dev container schema must be re-promoted on first sync from a dev device — this is the normal SwiftData + CloudKit workflow for any model change.

## Open Questions

Algorithm doc §A.11 lists three open implementation questions. Migration prompt §8 resolves all three for this change:

1. **`AllocationChange` / `LifecycleEvent` storage shape.** → Decided: SwiftData `@Model` (algorithm doc recommendation). Codable-blob alternative not used.
2. **`BudgetLifecycleService` keep-or-delete.** → Decided: Keep as adapter (overrides algorithm doc §A.8 Option 1).
3. **Specific Dates `effectiveAllocation` rule.** → Already specified by algorithm doc §A.4.2 step 2 (latest entry by `(effectiveFrom, lastModified)`). In this migration the code path is dead (no UI creates `.specificDates`); algorithm tests cover it for the future UI change.

No open questions remain for this migration.

## Doc alignment

This design aligns with:

- `docs/main-prd.md` §6.7 — the live-walker + asymmetric coupling wording is the contract this design implements. Tasks.md updates §6.7 to match.
- `docs/tech-design-doc.md` §3 (data model), §5.4 (service layer) — tasks.md updates both sections to reflect the new entities and the adapter role of `BudgetLifecycleService`.
- `docs/product-features-planning.md` — F-2.03 cadence picker removal is already partially synced; tasks.md confirms removal. F-7.05, F-7.06, F-7.07, F-2.08 stay Open. F-2.01, F-2.02, F-2.07 already reflect the new chip refresh rules (per main-prd.md sync status).
- `AGENTS.md` Cross-cutting concerns — this change has effectively no UI surface (one new code-only allocation row at Add time), so the four cross-cutting concerns (accessibility, localized strings, translations queue, Mixpanel events) have no new work in this change. Existing chip behavior — including its existing accessibility labels and Mixpanel events — is preserved.

No conflicts with the three canonical docs.
