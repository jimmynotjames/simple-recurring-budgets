## Why

The current carry-over algorithm (`BudgetCalculator.rollCarryOver`) is boundary-only: it folds completed periods into `Budget.carryOverAmount` and advances `carryOverLastProcessedDate` at period close, but never updates mid-period. The result is a stale chip — adding, editing, or deleting an expense in the current period does not refresh the Carry-over chip until the next period boundary is crossed. The rewrite replaces the boundary-only roll with a live walker plus an asymmetric coupling rule so the chip mirrors the user's committed state in real time, and lays the data-model foundation (allocation history, lifecycle events, `startDate` / `endDate`) that several Open features (F-7.05 per-budget start date, F-7.06 Pause/Resume, F-7.07 per-budget end date, F-2.08 Specific Dates) will sit on later. The Reset Cadences feature, which has been PAUSED since 2026-04-28, is permanently removed in the same change.

This change is **migration-scoped**: it lands the new algorithm and the schema rewrite, keeps the app behaviorally equivalent at the user-facing-feature level, and intentionally defers every new UI affordance (Start/End Date inputs, Pause/Resume action, Specific Dates period type chip, pre-start / post-end / paused chip overlays, expense date-bounds picker, Add Funds toggle) to its own future change.

## What Changes

- **BREAKING** Drop `Budget.allocation: Decimal`, `Budget.carryOverAmount: Decimal`, `Budget.carryOverLastProcessedDate: Date`, and `Budget.resetCadence: String` from the `Budget` `@Model`. Greenfield app, no production rows — no migration ceremony; wipe the simulator and move on (briefing §1).
- **BREAKING** Delete the `ResetCadence` enum, `BudgetPeriod.defaultResetCadence`, the `Budget.resetCadence` init parameter, and every "PAUSED — Reset Cadences" reference across docs and openspec specs (Reset Cadences is removed permanently, not paused — briefing §5.4).
- Add `Budget.startDate: Date?`, `Budget.endDate: Date?`, and `Budget.lastResetDate: Date?` (renamed from `carryOverLastResetDate`) to support live-walker math and the future lifecycle UI. All three are stored as `Date?` only because CloudKit-synced SwiftData fields must be optional; semantically `startDate` is always populated for a saved budget.
- Add two new `@Model` entities: `AllocationChange` (id, effectiveFrom, amount, lastModified, budget back-reference) and `LifecycleEvent` (id, kind: `LifecycleEventKind`, effectiveDate, lastModified, budget back-reference). Stored on `Budget` as `allocationChangesStorage: [AllocationChange]?` and `lifecycleEventsStorage: [LifecycleEvent]?` with non-optional computed accessors (CloudKit optionality pattern).
- Add `BudgetPeriod.specificDates` as a new enum case. The algorithm handles it; the Add/Edit Budget chip group continues to render only the four recurring period types in this migration.
- Replace `BudgetCalculator.rollCarryOver` and `BudgetCalculator.checkScheduledReset` with `BudgetCalculator.snapshot(budget:expenses:now:calendar:) -> BudgetSnapshot` — a single pure read entry point built on a live walker (`walkCarryOver`) plus asymmetric coupling (`currentPeriodSpillover`), with `allocationInEffect` and `isActive` helpers. Introduce a `RecurringBudgetPeriod` wrapper so `.specificDates` cannot reach `PeriodCalculator` at compile time. `PeriodCalculator` itself is untouched for the four recurring period types.
- Reshape `BudgetLifecycleService` into a thin compatibility adapter: `refreshAndSave(_:settings:context:)` keeps its public signature and `BudgetLifecycleResult` shape (so view sites need zero changes for the read path) but internally calls the new `snapshot(...)` and maps the result. Add new write-path methods `applyAllocationEdit`, `resetCarryOver(_:context:)`, and `resetBudget(_:context:)`. Deletion of the service is explicitly deferred to a future change (overrides algorithm doc §A.8 Option 1).
- Add a project-wide write-site rule: every user-initiated write that affects budget math (expense add / edit / delete, allocation edit, manual reset) bumps `Budget.lastModified` in the same `ModelContext.save()`. Views observe `.onChange(of: budget.lastModified)` to refresh the chip — this is the single reliable signal that fixes the mid-period stale-chip bug for all three write cases (Edit was previously unhandled when relying on `expenseItems.count`).
- Mechanical view-layer updates only (the minimum): `AddEditBudgetViewModel.save()` (Add mode) computes `startDate` per period type using the user's `AppSettings.weekStartDay` for weekly/biweekly anchoring (preserves F-5.01 behavior) and inserts an initial `AllocationChange` row in the same `context.save()`. `AddEditBudgetViewModel.save()` (Edit mode) routes allocation changes through `applyAllocationEdit`. Reset-budget and reset-carry-over call sites switch to the new service methods. No new UI fields, toolbar actions, chip overlays, screens, or copy.
- Update `openspec/specs/budget-math/spec.md`, `openspec/specs/budget-lifecycle/spec.md`, and `openspec/specs/data-models/spec.md` wholesale to reflect the new algorithm and schema. Update `docs/main-prd.md` §6.7, `docs/tech-design-doc.md` §3 + §5.4, and `docs/product-features-planning.md` (F-2.03 cadence picker removal confirmation; F-7.05 / F-7.06 stay Open). Do NOT update screen-level specs, `docs/ux-design-brief.md`, or `docs/analytics-spec.md` for the deferred UI work.

### Behavior changes that ride along (acceptable, user-visible)

- The Carry-over chip now refreshes mid-period in response to expense add / edit / delete — the bug fix that motivated the rewrite.
- Asymmetric live coupling lands live: overspending the current period immediately decreases Carry-over by the overshoot; negative-amount expenses (F-6.01 add-funds, reachable today only through the model layer) that push Remaining above Allocation immediately raise Carry-over by the excess. Ordinary mid-period slack (Remaining inside `[0, Allocation]`) waits for the period to close, as before.

No other user-visible behavior changes.

## Capabilities

### New Capabilities

_None._ Every spec touched by this migration already exists; the rewrite reshapes them in place.

### Modified Capabilities

- `budget-math`: Wholesale rewrite — replace `rollCarryOver` and `checkScheduledReset` requirements with `BudgetCalculator.snapshot(...)` plus `walkCarryOver`, `allocationInEffect`, `isActive`, and `currentPeriodSpillover` helpers; introduce `RecurringBudgetPeriod` wrapper for `PeriodCalculator`; delete the scheduled-reset requirement.
- `budget-lifecycle`: Rewrite `refreshAndSave` requirement as a pure read adapter that maps `BudgetSnapshot` to the legacy `BudgetLifecycleResult`; add new write-path requirements for `applyAllocationEdit`, `resetCarryOver`, and `resetBudget`; delete the scheduled-reset step.
- `data-models`: Reshape the `Budget` entity (drop `allocation`, `carryOverAmount`, `carryOverLastProcessedDate`, `resetCadence`; add `startDate`, `endDate`, `lastResetDate`, `allocationChangesStorage`, `lifecycleEventsStorage`); add `AllocationChange` and `LifecycleEvent` entities; add the `BudgetPeriod.specificDates` case; delete the `ResetCadence` enum; document the project-wide `Budget.lastModified` write-site rule.
- `schema-versioning`: Update `SchemaV1.swift` and `BudgetMigrationPlan.swift` to reflect the new schema shape. Per briefing §1, this is a greenfield rewrite — do not introduce `SchemaV2` or `VersionedSchema` machinery.

## Impact

**Affected code (Swift):**
- `Domain/BudgetCalculator.swift` — wholesale rewrite (new `snapshot(...)` entry point and helpers; delete `rollCarryOver`, `CarryOverRollResult`, `checkScheduledReset`, `ResetCheckResult`, `advanced(from:by:calendar:)`).
- `Domain/PeriodCalculator.swift` — untouched for the four recurring period types; only the `RecurringBudgetPeriod` wrapper is added in callers.
- `Domain/BudgetSnapshot.swift` (new), helper functions in `Domain/` (new).
- `Models/Budget.swift` — field set rewritten; new computed accessors for `allocationChanges` and `lifecycleEvents`.
- `Models/AllocationChange.swift` (new), `Models/LifecycleEvent.swift` (new), `Models/LifecycleEventKind.swift` (new).
- `Models/BudgetPeriod.swift` — add `.specificDates`; remove `defaultResetCadence`.
- `Models/ResetCadence.swift` — delete.
- `Models/SchemaV1.swift`, `Models/BudgetMigrationPlan.swift` — update to new shape (do not delete; no `SchemaV2`).
- `Services/BudgetLifecycleService.swift` — internals rewritten as adapter; three new write-path methods added.
- `ViewModels/AddEditBudgetViewModel.swift` — Add and Edit save paths updated.
- `Views/BudgetDetailView.swift`, `Views/BudgetsView.swift`, and any other chip-observing view — add `.onChange(of: budget.lastModified)` refresh trigger; `.onChange(of: budget.expenseItems.count)` becomes optional.
- All `ExpenseItem` write call sites (Add, Edit, Delete) — bump `budget.lastModified = now` in the same `context.save()`.
- Reset-Budget and Reset-Carry-Over call sites — switch to the new service methods.

**Affected tests:**
- Delete all tests for `rollCarryOver`, `checkScheduledReset`, `defaultResetCadence`, cadence-related lifecycle scenarios.
- Update tests asserting on `carryOverAmount` / `carryOverLastProcessedDate` to assert on `BudgetSnapshot` or the mapped `BudgetLifecycleResult` instead.
- Add the full snapshot / helper / walker / SwiftData round-trip / CloudKit-divergence test plan from algorithm doc §A.10 (including all **★** high-risk cases).
- Add adapter-mapping tests for `BudgetLifecycleService` covering each lifecycle state the legacy result exposes.
- Do NOT add UI tests for Pause/Resume, Start/End Date pickers, Specific Dates creation flows, or lifecycle chip overlays — those ship with the future features.

**Affected docs (in scope for this change):**
- `docs/main-prd.md` §6.7 — replace boundary-only wording with live-walker + asymmetric coupling; remove all PAUSED Reset Cadences notes.
- `docs/tech-design-doc.md` §3 (data model), §5.4 (service layer) — reflect new entities and the adapter role of `BudgetLifecycleService`; remove Reset Cadences references.
- `docs/product-features-planning.md` — confirm F-2.03 cadence picker removal; F-7.05 / F-7.06 / F-7.07 / F-2.08 stay Open.
- `openspec/specs/budget-math/spec.md`, `openspec/specs/budget-lifecycle/spec.md`, `openspec/specs/data-models/spec.md` — wholesale updates per the modified-capabilities list above.

**Out-of-scope docs (NOT updated in this change):**
- `openspec/specs/add-edit-budget-screen/spec.md`, `openspec/specs/budgets-screen/spec.md`, `openspec/specs/budget-detail-screen/spec.md`, `openspec/specs/add-edit-expense-screen/spec.md` — no new UI affordances shipping. Exception: any sentence that currently describes the *old* boundary-only `rollCarryOver` refresh trigger or the PAUSED Reset Cadences feature needs the phrase replaced, but no new scenarios are added.
- `docs/ux-design-brief.md` — no new lifecycle-state UI shipping.
- `docs/analytics-spec.md` — no new events shipping; existing `budget_edited`, `expense_added`, etc. keep firing exactly as today.

**Dependencies / systems:**
- SwiftData schema is reshaped — the simulator must be wiped during dev. App Store: not deployed; no production users (briefing §1).
- CloudKit sync — new entities (`AllocationChange`, `LifecycleEvent`) follow the existing CloudKit-optional-relationship pattern. Cross-device convergence tests are included in the `data-models` test plan.
- Mixpanel: existing events unchanged; new event properties and the `budget_paused` / `budget_resumed` events are deferred to the future UI changes.

## Doc alignment

Briefing §2.11 lists every doc that *eventually* updates for the full rewrite. This migration covers a strict subset — see the in-scope vs out-of-scope split under **Impact** above. The principle, per migration prompt §4: *does the user see anything new in the app because of this change?* If no (the algorithm changed but the UI didn't), skip the doc update.

No conflicts with the three canonical docs (`docs/main-prd.md`, `docs/product-features-planning.md`, `docs/tech-design-doc.md`) — this migration explicitly aligns them with the rewritten algorithm and schema (the three sub-bullets under "Affected docs") while leaving the deferred UI work to future changes.
