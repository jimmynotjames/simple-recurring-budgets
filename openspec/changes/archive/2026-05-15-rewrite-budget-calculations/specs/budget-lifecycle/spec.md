## MODIFIED Requirements

### Requirement: Eager refreshAndSave entry point

The system SHALL provide a `BudgetLifecycleService.refreshAndSave(_:settings:context:now:calendar:)` entry point as a compatibility seam between view sites and the new pure read `BudgetCalculator.snapshot(...)`. The method SHALL:

1. Call `BudgetCalculator.snapshot(budget:expenses:now:calendar:)` to compute a `BudgetSnapshot`.
2. Map the snapshot to a `BudgetLifecycleResult` (see "BudgetLifecycleResult returned for display") and return it.
3. NOT mutate `Budget`, `ExpenseItem`, `AllocationChange`, or `LifecycleEvent` rows. The walker is live; there are no fields on `Budget` for the read path to persist.
4. NOT call `ModelContext.save()` from the read path.

The method's name (`refreshAndSave`) is preserved for view-site compatibility. The "Save" semantic is a misnomer after this change and will be addressed by a future renaming change.

All time-dependent inputs (`now`, `calendar`) SHALL be parameters with production defaults (`Date()`, `Calendar.autoupdatingCurrent`) so that tests can inject deterministic values.

The biweekly anchor used for period math SHALL be derived from `Budget.startDate` per the `budget-math` capability. `AppSettings.weekStartDay` SHALL NOT be consulted from this service at math-time.

#### Scenario: refreshAndSave is a pure read pass-through

- **WHEN** `BudgetLifecycleService.refreshAndSave` is called with a budget, app settings, a model context, a fixed `now`, and a fixed calendar
- **THEN** the service calls `BudgetCalculator.snapshot(...)` exactly once, does not mutate the budget or its child rows, does not call `context.save()`, and returns a `BudgetLifecycleResult` mapped from the snapshot

#### Scenario: Idempotent across repeated calls

- **WHEN** `refreshAndSave` is called twice in a row with the same `now` and no intervening writes
- **THEN** both calls return equal `BudgetLifecycleResult` values, and the budget's stored fields are unchanged between calls

### Requirement: BudgetLifecycleResult returned for display

The system SHALL return a `BudgetLifecycleResult` value with the following fields, populated from the underlying `BudgetSnapshot`:

- `remaining: Decimal` ← `snapshot.remaining`.
- `carryOverAmount: Decimal` ← `snapshot.carryOver ?? 0`. The `?? 0` is a defensive fallback for the `.specificDates` case (which returns `nil`); no UI in this migration creates a `.specificDates` budget, so the fallback is never triggered in normal flow. Future changes that ship Specific Dates UI SHALL replace this with a typed result that does not require the fallback.
- `periodStart: Date` ← `snapshot.effectivePeriodStart`.
- `periodEnd: Date` ← `snapshot.effectivePeriodEnd`.

Additional snapshot fields (`lifecycleState`, `effectiveAllocation`) SHALL NOT be exposed through `BudgetLifecycleResult` in this change; they will be plumbed when the new lifecycle UI features ship.

#### Scenario: Result reflects snapshot state

- **WHEN** `BudgetCalculator.snapshot(...)` returns `remaining: 7.50, carryOver: 12.00, effectivePeriodStart: 2026-04-15 00:00, effectivePeriodEnd: 2026-04-16 00:00`
- **THEN** the returned `BudgetLifecycleResult` has `remaining = 7.50, carryOverAmount = 12.00, periodStart = 2026-04-15 00:00, periodEnd = 2026-04-16 00:00`

#### Scenario: Nil snapshot.carryOver maps to 0 (defensive)

- **WHEN** a `.specificDates` budget somehow reaches this seam (out-of-flow code path) and the snapshot returns `carryOver: nil`
- **THEN** `BudgetLifecycleResult.carryOverAmount` is `0`

#### Scenario: Remaining is independent of carry-over

- **WHEN** the budget has a non-zero carry-over after snapshot computation
- **THEN** `BudgetLifecycleResult.remaining` reflects only the current period's `effectiveAllocation − net expenses in the period`; it is not offset by the carry-over amount

#### Scenario: Remaining may be negative

- **WHEN** the sum of this period's expenses exceeds `effectiveAllocation`
- **THEN** `BudgetLifecycleResult.remaining` is negative

### Requirement: Screen / ViewModel consumption contract

Screens (and any escalated ViewModels per `docs/tech-design-doc.md` §2.1) SHALL call `refreshAndSave` eagerly on budget access — at minimum on screen appearance, on `scenePhase == .active`, and via `.onChange(of: budget.lastModified)` so that mid-period writes refresh the chip. Screens that have not escalated to a ViewModel invoke `refreshAndSave` directly using `@Environment(\.modelContext)` and the injected `AppSettings`. Screens that have escalated to a ViewModel expose a method taking `(settings: AppSettings, context: ModelContext, ...)` at the call site and forward to the service.

Screens and ViewModels SHALL treat the returned `BudgetLifecycleResult` as the source of truth for current-period display values rather than recomputing them. Neither screens nor ViewModels SHALL call `BudgetCalculator.snapshot(...)` directly for the eager access flow — `BudgetLifecycleService` is the single entry point.

#### Scenario: Screen calls refreshAndSave on screen appearance

- **WHEN** a Budgets or Budget screen becomes visible
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.refreshAndSave` for each displayed budget and binds the returned `BudgetLifecycleResult` values to the view

#### Scenario: Screen calls refreshAndSave on scene activation

- **WHEN** the app transitions to `scenePhase == .active` while a budget is displayed
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.refreshAndSave` so any period boundaries crossed while inactive are reflected before the next frame

#### Scenario: Screen calls refreshAndSave on Budget.lastModified change

- **WHEN** any user-initiated write that bumps `Budget.lastModified` lands (expense add/edit/delete, allocation edit, manual reset)
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.refreshAndSave` so the chip reflects the new state without waiting for a period boundary

## REMOVED Requirements

### Requirement: Single write-back path from calculator results to Budget

**Reason**: The new read path does not write to `Budget` at all — the walker is live; there are no `carryOverAmount` / `carryOverLastProcessedDate` fields to persist (both are removed from the schema per `data-models`). The "single write-back path" concern no longer exists for the read flow.

**Migration**: Write paths for math-affecting state moved to dedicated write-path methods on `BudgetLifecycleService` (see ADDED Requirements: "Allocation edit write-path", "Manual reset carry-over write-path", "Reset budget write-path"). These are the new single entry points for the values they manage.

### Requirement: Single save per refreshAndSave, only when state changed

**Reason**: `refreshAndSave` no longer mutates state, so it never calls `context.save()`. The invariant is preserved trivially.

**Migration**: No replacement needed for the read path. Write-path methods (see ADDED Requirements below) each call `context.save()` exactly once at the end of their work and bump `Budget.lastModified = now` so observing views refresh.

### Requirement: Multi-period catch-up applies through the same single-save path

**Reason**: The walker computes catch-up live on every read; there is no persisted `lastProcessedDate` to advance and no `save()` to coordinate. Multi-period catch-up is handled inside `walkCarryOver(...)` (see the `budget-math` capability).

**Migration**: No replacement. Multi-period correctness is covered by walker tests in the `budget-math` capability.

## ADDED Requirements

### Requirement: Allocation edit write-path

The system SHALL provide `BudgetLifecycleService.applyAllocationEdit(_ budget: Budget, newAmount: Decimal, context: ModelContext, now: Date, calendar: Calendar)` for view sites that change a budget's allocation in Edit mode. The method SHALL implement the algorithm doc §A.6.2 insert-or-mutate convention:

1. Compute `currentPeriodStart` for the budget using its `RecurringBudgetPeriod` (or `startDate` for `.specificDates`).
2. If an `AllocationChange` row already exists with `effectiveFrom == currentPeriodStart`, update its `amount` to `newAmount` and bump its `lastModified = now`.
3. Otherwise, insert a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: newAmount, lastModified: now)` linked to the budget.
4. Bump `Budget.lastModified = now`.
5. Call `context.save()` exactly once.

The method SHALL NOT mutate any other `AllocationChange` row. Prior periods continue to consult their historical allocations via `allocationInEffect`.

#### Scenario: First allocation edit in the current period inserts a new row

- **WHEN** the budget has a single `AllocationChange(effectiveFrom: startDate, amount: 20.00)` and the user changes allocation to 25.00 mid-period
- **THEN** a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: 25.00, lastModified: now)` is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Repeated edits in the same period mutate the existing row

- **WHEN** an `AllocationChange` already exists with `effectiveFrom == currentPeriodStart` and the user changes the allocation again
- **THEN** the existing row's `amount` is overwritten with the new value, its `lastModified` is bumped, no new row is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Prior periods are unaffected

- **WHEN** the user changes the allocation in the current period
- **THEN** no `AllocationChange` row whose `effectiveFrom < currentPeriodStart` is mutated, and the walker continues to use the historical amounts for those periods

### Requirement: Manual reset carry-over write-path

The system SHALL provide `BudgetLifecycleService.resetCarryOver(_ budget: Budget, context: ModelContext, now: Date)` for the Reset Carry-Over button. The method SHALL:

1. Set `Budget.lastResetDate = now`.
2. Bump `Budget.lastModified = now`.
3. Call `context.save()` exactly once.

The walker (in the `budget-math` capability) trims its walk window to periods whose end is strictly after `Budget.lastResetDate`, so writing `lastResetDate` is sufficient — no `carryOverAmount` field exists to zero.

#### Scenario: Reset Carry-Over writes lastResetDate

- **WHEN** the user taps Reset Carry-Over at `now = 2026-04-15 10:00`
- **THEN** `Budget.lastResetDate = 2026-04-15 10:00`, `Budget.lastModified = 2026-04-15 10:00`, and `context.save()` is called once

#### Scenario: Walker output drops to current-period spillover after reset

- **WHEN** Reset Carry-Over is invoked and the next `BudgetCalculator.snapshot(...)` runs
- **THEN** the walker contribution is 0 (every prior completed period's end is at or before `lastResetDate`), and `carryOver` equals `currentPeriodSpillover` alone

### Requirement: Reset budget write-path

The system SHALL provide `BudgetLifecycleService.resetBudget(_ budget: Budget, context: ModelContext, now: Date)` for the Reset Budget toolbar action. The method SHALL:

1. Delete every `ExpenseItem` whose `budget == budget`.
2. Set `Budget.lastResetDate = now`.
3. Bump `Budget.lastModified = now`.
4. Call `context.save()` exactly once.

The method SHALL NOT mutate `AllocationChange` or `LifecycleEvent` rows — the budget's lifecycle history is preserved.

#### Scenario: Reset Budget deletes all expenses and zeros carry-over

- **WHEN** a budget has three ExpenseItems and the user invokes Reset Budget at `now`
- **THEN** all three ExpenseItems are deleted, `Budget.lastResetDate = now`, `Budget.lastModified = now`, `context.save()` is called once, and the next snapshot's `remaining` equals `effectiveAllocation` while `carryOver` reflects only the (empty) current period

#### Scenario: AllocationChange rows are preserved across Reset Budget

- **WHEN** a budget has two AllocationChange rows and the user invokes Reset Budget
- **THEN** both AllocationChange rows remain in the store and `allocationInEffect(...)` continues to return the latest applicable amount

## Doc alignment

`docs/tech-design-doc.md` §5.4 (service layer) describes the previous orchestration sequence. This delta replaces that description with the adapter-plus-three-write-paths shape; the tasks artifact in this change updates the doc accordingly. No conflicts with `docs/main-prd.md` (which describes the user-facing contract, not the service shape).
