# Budget lifecycle

Orchestrates the pure-read snapshot entry point, write-path methods, and display-ready remaining/period window for a `Budget`, binding `BudgetCalculator` output to SwiftData via a single service. Synced from change `rewrite-budget-calculations` (2026-05-15). Updated from change `pause-resume-budget` (2026-05-16). Updated from change `specific-dates-period` (2026-05-18).
## Requirements
### Requirement: Pure-read result(for:) entry point

The system SHALL provide a `BudgetLifecycleService.result(for:now:calendar:weekStart:)` entry point as a compatibility seam between view sites and the pure read `BudgetCalculator.snapshot(...)`. The method SHALL:

1. Call `BudgetCalculator.snapshot(budget:expenses:now:calendar:weekStart:)` to compute a `BudgetSnapshot`.
2. Map the snapshot to a `BudgetLifecycleResult` (see "BudgetLifecycleResult returned for display") and return it.
3. NOT mutate `Budget`, `ExpenseItem`, `AllocationChange`, or `LifecycleEvent` rows. The walker is live; there are no fields on `Budget` for the read path to persist.
4. NOT accept a `ModelContext` or call `ModelContext.save()` from the read path.

All time-dependent inputs (`now`, `calendar`) SHALL be parameters with production defaults (`Date()`, `Calendar.autoupdatingCurrent`) so that tests can inject deterministic values. The `weekStart: Weekday` parameter SHALL have **no default value**; production callers SHALL pass `AppSettings.weekStartDay` (read at the call site — the service itself remains settings-free and pure).

The biweekly anchor used for period math SHALL be derived from `Budget.startDate` per the `budget-math` capability; the weekly grid SHALL come from the caller-provided `weekStart`.

#### Scenario: result(for:) is a pure read pass-through

- **WHEN** `BudgetLifecycleService.result(for:)` is called with a budget, a fixed `now`, a fixed calendar, and a `weekStart`
- **THEN** the service calls `BudgetCalculator.snapshot(...)` exactly once, does not mutate the budget or its child rows, does not touch any model context, and returns a `BudgetLifecycleResult` mapped from the snapshot

#### Scenario: Idempotent across repeated calls

- **WHEN** `result(for:)` is called twice in a row with the same `now`, the same `weekStart`, and no intervening writes
- **THEN** both calls return equal `BudgetLifecycleResult` values, and the budget's stored fields are unchanged between calls

### Requirement: BudgetLifecycleResult returned for display

The system SHALL return a `BudgetLifecycleResult` value with the following fields, populated from the underlying `BudgetSnapshot`:

- `remaining: Decimal` ← `snapshot.remaining`.
- `carryOverAmount: Decimal` ← `snapshot.carryOver ?? 0`. The `?? 0` flattens the `nil` that `BudgetCalculator.snapshot` returns for `.specificDates` budgets. Per F-2.08, the carry-over chip is **hidden** for specificDates budgets (chip-hiding work lives in `BudgetDetailView` / `BudgetRowView` and ships with the F-2.08 UI). Until F-2.08 ships, this fallback is unreachable in normal flow. The F-2.08 change MUST either (a) stop calling `result(for:)` for specificDates budgets, or (b) replace `BudgetLifecycleResult` with a sum type that preserves the `nil`.
- `periodStart: Date` ← `snapshot.effectivePeriodStart`.
- `periodEnd: Date` ← `snapshot.effectivePeriodEnd`.
- `lifecycleState: BudgetLifecycleState` ← `snapshot.lifecycleState`. Used by view sites to switch between the active, paused, pre-start, and post-end presentations. The `.paused` value flips moment-granular per the `budget-math` "Moment-granular UI pause classification" requirement — i.e., view sites SHALL see `lifecycleState == .paused` as soon as a `.pause` event's `effectiveDate` is at or before `now`, regardless of where `now` falls inside the pause-action period.
- `pausedSince: Date?` — when `lifecycleState == .paused`, the `effectiveDate` of the most recent `.pause` `LifecycleEvent` for the budget that is not followed by a later `.resume` event. When `lifecycleState != .paused`, `nil`.

`effectiveAllocation` from the snapshot SHALL NOT be exposed through `BudgetLifecycleResult` in this change; it will be plumbed when the start-date / end-date input UI ships (F-7.05 / F-7.07).

#### Scenario: Result reflects snapshot state

- **WHEN** `BudgetCalculator.snapshot(...)` returns `remaining: 7.50, carryOver: 12.00, effectivePeriodStart: 2026-04-15 00:00, effectivePeriodEnd: 2026-04-16 00:00, lifecycleState: .active`
- **THEN** the returned `BudgetLifecycleResult` has `remaining = 7.50, carryOverAmount = 12.00, periodStart = 2026-04-15 00:00, periodEnd = 2026-04-16 00:00, lifecycleState = .active, pausedSince = nil`

#### Scenario: Nil snapshot.carryOver maps to 0 (defensive)

- **WHEN** a `.specificDates` budget somehow reaches this seam (out-of-flow code path) and the snapshot returns `carryOver: nil`
- **THEN** `BudgetLifecycleResult.carryOverAmount` is `0`

#### Scenario: Remaining is independent of carry-over

- **WHEN** the budget has a non-zero carry-over after snapshot computation
- **THEN** `BudgetLifecycleResult.remaining` reflects only the current period's `effectiveAllocation − net expenses in the period`; it is not offset by the carry-over amount

#### Scenario: Remaining may be negative

- **WHEN** the sum of this period's expenses exceeds `effectiveAllocation`
- **THEN** `BudgetLifecycleResult.remaining` is negative

#### Scenario: pausedSince is the effectiveDate of the most recent unbalanced pause

- **WHEN** the budget has lifecycle events `[(.pause, 2026-04-10), (.resume, 2026-04-15), (.pause, 2026-05-01)]` and `now = 2026-05-10`
- **THEN** `BudgetLifecycleResult.lifecycleState == .paused` and `BudgetLifecycleResult.pausedSince == 2026-05-01`

#### Scenario: pausedSince is nil when budget is not currently paused

- **WHEN** the budget's most recent `LifecycleEvent` is `(.resume, …)` or there are no `LifecycleEvent` rows
- **THEN** `BudgetLifecycleResult.pausedSince == nil`

#### Scenario: lifecycleState flips paused immediately on mid-period pause

- **WHEN** the budget has lifecycle event `[(.pause, 2026-05-16 10:00)]` and `now = 2026-05-16 10:01` (one minute later, same period)
- **THEN** `BudgetLifecycleResult.lifecycleState == .paused` and `BudgetLifecycleResult.pausedSince == 2026-05-16 10:00`

### Requirement: Pause budget write-path

The system SHALL provide `BudgetLifecycleService.pauseBudget(_ budget: Budget, context: ModelContext, now: Date, calendar: Calendar, weekStart: Weekday) -> Bool` for the Pause Budget action. The `weekStart` parameter (no default; production callers pass `AppSettings.weekStartDay`) is threaded into the eligibility snapshot. The method SHALL implement the eligibility, clamping, and write rules below.

**Eligibility.** The method SHALL return `false` without mutating any row, calling `context.save()`, or otherwise changing observable state when any of the following holds:

1. `BudgetPeriod(rawValue: budget.period) == .specificDates` — Specific Dates budgets are not pausable (`docs/budget-calculations-rewrite-reqs.md` §5.5 / §6.7 case 14).
2. The budget's current `lifecycleState` (as computed by `BudgetCalculator.snapshot(...).lifecycleState`) is already `.paused` — no redundant write.
3. The budget's current `lifecycleState` is `.postEnd` — pausing a terminal budget is a no-op.

**Effective date clamp.** When the action is accepted, the method SHALL compute `effectiveDate` as `now` clamped into `[budget.startDate ?? .distantPast, budget.endDate ?? .distantFuture]`. The lower clamp implements `docs/budget-calculations-rewrite-reqs.md` §5.5 "Pause while `startDate` is in the future" — the pause SHALL be recorded as if it occurred on `startDate`. The upper clamp matches the `.postEnd` rejection above and is defensive.

**Write sequence.** When accepted, the method SHALL, in order:

1. Insert a new `LifecycleEvent(budget: budget, kind: .pause, effectiveDate: clampedEffectiveDate)` into the passed `ModelContext`.
2. Set `Budget.lastModified = now` (per the data-models `Budget.lastModified` write-site rule).
3. Call `context.save()` exactly once.
4. Return `true`.

The method SHALL NOT mutate `Budget.startDate`, `Budget.endDate`, `AllocationChange` rows, `ExpenseItem` rows, or any other `LifecycleEvent` row.

#### Scenario: Pause on an active budget inserts one event and bumps lastModified

- **WHEN** the user taps Pause on a daily budget whose `lifecycleState` is `.active` at `now = 2026-05-16 10:00`
- **THEN** a single `LifecycleEvent(kind: .pause, effectiveDate: 2026-05-16 10:00)` is inserted, `Budget.lastModified = 2026-05-16 10:00`, `context.save()` is called exactly once, no other rows are mutated, and the method returns `true`

#### Scenario: Pause clamps to startDate when budget has not yet started

- **WHEN** the user taps Pause at `now = 2026-04-10` on a budget with `startDate = 2026-05-01`
- **THEN** the inserted `LifecycleEvent` has `effectiveDate = 2026-05-01 00:00` (the budget's `startDate`), `Budget.lastModified = 2026-04-10`, and the method returns `true`

#### Scenario: Pause is rejected for Specific Dates budgets

- **WHEN** the user (or a direct-CloudKit write path) attempts to call `pauseBudget(...)` on a budget whose `period == "specificDates"`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

#### Scenario: Pause is rejected when budget is already paused

- **WHEN** `pauseBudget(...)` is called on a budget whose current `lifecycleState` is `.paused`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

#### Scenario: Pause is rejected when budget is past endDate

- **WHEN** `pauseBudget(...)` is called on a budget whose `endDate` is in the past relative to `now`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

### Requirement: Resume budget write-path

The system SHALL provide `BudgetLifecycleService.resumeBudget(_ budget: Budget, context: ModelContext, now: Date, calendar: Calendar, weekStart: Weekday) -> Bool` for the Resume Budget action. The `weekStart` parameter (no default; production callers pass `AppSettings.weekStartDay`) is threaded into the eligibility snapshot. The method SHALL implement the eligibility and write rules below.

**Eligibility.** The method SHALL return `false` without mutating any row, calling `context.save()`, or otherwise changing observable state when any of the following holds:

1. `BudgetPeriod(rawValue: budget.period) == .specificDates` — Specific Dates budgets are not resumable.
2. The budget's current `lifecycleState` is `.active` or `.preStart` — no redundant write.
3. The budget's current `lifecycleState` is `.postEnd` — `endDate` is terminal; resume SHALL be rejected (`docs/product-features-planning.md` F-7.06 and F-7.07; `docs/budget-calculations-rewrite-reqs.md` §6.7 case 12).

**Write sequence.** When accepted, the method SHALL, in order:

1. Insert a new `LifecycleEvent(budget: budget, kind: .resume, effectiveDate: now)` into the passed `ModelContext`. The effective date for resume is `now` directly; no `startDate` clamping is required because if `now < startDate` the budget is already in the `.preStart` state, which falls under the redundant-write rejection above.
2. Set `Budget.lastModified = now`.
3. Call `context.save()` exactly once.
4. Return `true`.

The method SHALL NOT mutate `Budget.startDate`, `Budget.endDate`, `AllocationChange` rows, `ExpenseItem` rows, or any other `LifecycleEvent` row.

#### Scenario: Resume on a paused budget inserts one event and bumps lastModified

- **WHEN** the user taps Resume on a budget whose `lifecycleState` is `.paused` at `now = 2026-05-20 09:00`
- **THEN** a single `LifecycleEvent(kind: .resume, effectiveDate: 2026-05-20 09:00)` is inserted, `Budget.lastModified = 2026-05-20 09:00`, `context.save()` is called exactly once, no other rows are mutated, and the method returns `true`

#### Scenario: Resume is rejected past endDate

- **WHEN** the user (or a direct-CloudKit write path) calls `resumeBudget(...)` on a budget whose `endDate` is before `now`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

#### Scenario: Resume is rejected for Specific Dates budgets

- **WHEN** `resumeBudget(...)` is called on a budget whose `period == "specificDates"`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

#### Scenario: Resume is rejected when budget is already active

- **WHEN** `resumeBudget(...)` is called on a budget whose current `lifecycleState` is `.active`
- **THEN** no `LifecycleEvent` is inserted, `Budget.lastModified` is unchanged, `context.save()` is not called, and the method returns `false`

### Requirement: Pause and resume separate UI state from carry-over math

The pause and resume write paths SHALL produce `LifecycleEvent` rows that are consumed by two distinct classifiers inside `BudgetCalculator.snapshot(...)`:

- **Math (period-granular):** `LifecycleClassification.isActive(period:lifecycleEvents:)` continues to govern carry-over walker accrual and the `remaining = 0` short-circuit for fully-paused periods per the period-granular rules already shipped:
  - The period containing a `.pause` event remains active for math (the snapshot continues to compute carry-over normally for that period).
  - Every period strictly after a `.pause` event and strictly before the next `.resume` event is paused for math; paused periods contribute 0 to the carry-over walk.
  - The period containing a `.resume` event is fully active for math (no proration).
- **UI (moment-granular):** the moment-granular `isPausedAtMoment(now:sortedLifecycleEvents:)` classifier (see `budget-math` "Moment-granular UI pause classification") governs `BudgetSnapshot.lifecycleState` — and therefore `BudgetLifecycleResult.lifecycleState` — flipping to `.paused` immediately when a `.pause` event's `effectiveDate` is at or before `now`.

The pause/resume write paths SHALL NOT introduce any classification logic of their own; their only responsibility is to insert the correct event row. Both classifiers consume the same `LifecycleEvent` source of truth.

#### Scenario: Pause-action period is still active for math

- **WHEN** the user pauses a daily budget mid-day and the snapshot is computed at the end of that same day
- **THEN** the pause-action day's carry-over contribution is computed normally (`allocationInEffect - sum(expenses)`), per `LifecycleClassification.isActive(period:lifecycleEvents:)`

#### Scenario: Pause-action period flips paused immediately for UI

- **WHEN** the user pauses a daily budget at 2026-05-16 10:00 and the snapshot is computed at 2026-05-16 10:01
- **THEN** `BudgetLifecycleResult.lifecycleState == .paused` even though the pause-action day is still active for the math classifier

#### Scenario: Period immediately after the pause-action period is paused

- **WHEN** the user pauses a daily budget on day D and the snapshot is computed on day D+1 with no intervening resume
- **THEN** day D+1's carry-over contribution is 0 (math classifier returns `false`), and `BudgetLifecycleResult.lifecycleState == .paused` (UI classifier returns `true`)

#### Scenario: Resume-action period is fully active

- **WHEN** the user resumes a daily budget at any moment during day R
- **THEN** day R contributes a full day's allocation to the carry-over walk (no proration), and `BudgetLifecycleResult.lifecycleState == .active` from the resume moment onward

#### Scenario: Same-period pause then resume nets to active UI

- **WHEN** the user pauses at 2026-05-16 09:00 and resumes at 2026-05-16 11:00, and the snapshot is computed at 2026-05-16 12:00
- **THEN** `BudgetLifecycleResult.lifecycleState == .active` (moment-granular UI sees the resume as the latest event ≤ now) and the day's carry-over math is unaffected by the round-trip

### Requirement: Screen / ViewModel consumption contract

Screens (and any escalated ViewModels per `docs/tech-design-doc.md` §2.1) SHALL call `result(for:)` eagerly on budget access — at minimum on screen appearance, on `scenePhase == .active`, via `.onChange(of: budget.lastModified)` so that mid-period writes refresh the chip, and via `.onChange(of: settings.weekStartDay)` so that a week-start change (local or synced from another device) re-grids weekly budgets immediately. Because `result(for:)` is a pure read, no `ModelContext` is required at the call site; the call site reads `AppSettings.weekStartDay` solely to supply the `weekStart` parameter.

Screens and ViewModels SHALL treat the returned `BudgetLifecycleResult` as the source of truth for current-period display values rather than recomputing them. Neither screens nor ViewModels SHALL call `BudgetCalculator.snapshot(...)` directly for the eager access flow — `BudgetLifecycleService` is the single entry point.

#### Scenario: Screen calls result(for:) on screen appearance

- **WHEN** a Budgets or Budget screen becomes visible
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.result(for:)` for each displayed budget and binds the returned `BudgetLifecycleResult` values to the view

#### Scenario: Screen calls result(for:) on scene activation

- **WHEN** the app transitions to `scenePhase == .active` while a budget is displayed
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.result(for:)` so any period boundaries crossed while inactive are reflected before the next frame

#### Scenario: Screen calls result(for:) on Budget.lastModified change

- **WHEN** any user-initiated write that bumps `Budget.lastModified` lands (expense add/edit/delete, allocation edit, manual reset)
- **THEN** the screen (or its ViewModel) calls `BudgetLifecycleService.result(for:)` so the chip reflects the new state without waiting for a period boundary

#### Scenario: Screen calls result(for:) on week-start change

- **WHEN** `AppSettings.weekStartDay` changes — whether confirmed locally in Settings or applied by the iCloud key-value store external-change observer
- **THEN** every visible budget surface re-invokes `BudgetLifecycleService.result(for:)` with the new `weekStart`, so weekly budgets re-grid without requiring navigation or scene transitions

### Requirement: Allocation edit write-path

The system SHALL provide `BudgetLifecycleService.applyAllocationEdit(_ budget: Budget, newAmount: Decimal, context: ModelContext, now: Date, calendar: Calendar, weekStart: Weekday)` for view sites that change a budget's allocation in Edit mode. The method SHALL implement the algorithm doc §A.6.2 insert-or-mutate convention — keyed so the write, the live read, and the walker always agree — with a period-type carve-out for `.specificDates`:

**For recurring periods (`.daily`, `.weekly`, `.biweekly`, `.monthly`):**

1. Compute `currentPeriodStart` for the budget using its `RecurringBudgetPeriod` (weekly periods use the caller-provided `weekStart`).
2. Compute the edit key: `key = max(currentPeriodStart, calendar.startOfDay(for: budget.effectiveStartDate))` — the same instant the snapshot's live read uses for `allocationInEffect`.
3. Locate the **governing row**: the latest `AllocationChange` (by `(effectiveFrom, lastModified)`) with `effectiveFrom <= key`. If a governing row exists and its `effectiveFrom >= currentPeriodStart` (it took effect within the current period), update its `amount` to `newAmount` and bump its `lastModified = now`.
4. Otherwise, insert a new `AllocationChange(effectiveFrom: key, amount: newAmount, lastModified: now)` linked to the budget.
5. Bump `Budget.lastModified = now`.
6. Call `context.save()` exactly once.

For budgets whose `startDate` is aligned to the period grid, `key == currentPeriodStart` and this rule is byte-for-byte the previous insert-or-mutate convention. For budgets whose first period starts mid-grid (a monthly budget created mid-month; a weekly budget whose `startDate` is not on the global week-start day), the rule mutates the initial `startDate` row instead of inserting a shadowed row at the grid boundary — guaranteeing the live read (`allocationInEffect` at `key`) and the walker's closed-period lookup (grid boundary with earliest-row fallback) both observe the edit (fixes #247).

The method SHALL NOT mutate any other `AllocationChange` row for recurring periods. Prior periods continue to consult their historical allocations via `allocationInEffect` (forward-only semantics per F-2.03).

**For `.specificDates` (latest-wins whole-window overwrite, per F-2.08):**

1. Locate the most-recent `AllocationChange` for the budget by `(effectiveFrom, lastModified)`. For a `.specificDates` budget this is always the initial row inserted at budget creation (with `effectiveFrom == Budget.startDate`).
2. If that row's `amount != newAmount`, write `amount = newAmount` and `lastModified = now`. If the amount is unchanged, no row mutation occurs and the method SHALL be a no-op.
3. SHALL NOT insert a new `AllocationChange` row — `.specificDates` has only one period (the entire window) and there is no audit-trail requirement (the prior figure is not retrievable per F-2.08).
4. When a write occurred, bump `Budget.lastModified = now` and call `context.save()` exactly once. When the amount was unchanged, do not bump `lastModified` or save.

This `.specificDates` branch is the documented exception to the forward-only allocation-edit rule that applies to recurring periods.

#### Scenario: First allocation edit in the current period inserts a new row (recurring)

- **WHEN** the budget has a single `AllocationChange(effectiveFrom: startDate, amount: 20.00)` and the user changes allocation to 25.00 mid-period for a `.daily` budget
- **THEN** a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: 25.00, lastModified: now)` is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Repeated edits in the same period mutate the existing row (recurring)

- **WHEN** an `AllocationChange` already exists with `effectiveFrom == currentPeriodStart` and the user changes the allocation again for a `.daily` budget
- **THEN** the existing row's `amount` is overwritten with the new value, its `lastModified` is bumped, no new row is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Prior periods are unaffected (recurring)

- **WHEN** the user changes the allocation in the current period of a recurring budget
- **THEN** no `AllocationChange` row governing a prior period is mutated, and the walker continues to use the historical amounts for those periods

#### Scenario: Mid-month-start monthly edit mutates the startDate row — live and walker agree (#247)

- **WHEN** a monthly budget has `startDate = 2026-01-15` with its initial `AllocationChange(effectiveFrom: 2026-01-15, amount: 500)` and the user edits the allocation to 600 on 2026-01-31
- **THEN** the initial row is mutated in place (`amount = 600`, exactly one `AllocationChange` row exists), the live snapshot's `effectiveAllocation` is 600, and after January closes the walker credits January at 600 — the two reads never disagree

#### Scenario: Weekly first-partial-period edit mutates the startDate row (#247 under the global grid)

- **WHEN** a weekly budget has `startDate = Wednesday 2026-04-01` (initial row at Apr 1, amount 100), `weekStart = .sunday`, and the user edits the allocation to 150 on Friday 2026-04-03
- **THEN** the key is `max(2026-03-29, 2026-04-01) = 2026-04-01`, the initial row is mutated to 150 (row count stays 1), the live `effectiveAllocation` is 150, and after the partial week closes the walker credits it at 150

#### Scenario: Specific Dates allocation edit overwrites the single row

- **WHEN** the budget is `.specificDates` with `startDate = 2026-05-08`, `endDate = 2026-05-25`, a single `AllocationChange(effectiveFrom: 2026-05-08, amount: 1500.00, lastModified: 2026-05-07)`, and the user changes allocation to 1800.00 mid-window at `now = 2026-05-15`
- **THEN** the existing row's `amount` is overwritten to 1800.00, `lastModified` is bumped to `now`, no new `AllocationChange` row is inserted, `Budget.lastModified = now`, and `context.save()` is called once

#### Scenario: Specific Dates no-op edit does not write

- **WHEN** the budget is `.specificDates` with a single `AllocationChange(amount: 1500.00)` and the user "edits" the allocation to the same value 1500.00
- **THEN** no `AllocationChange` row is mutated, `Budget.lastModified` is NOT bumped, and `context.save()` is NOT called

#### Scenario: Specific Dates edit does not preserve audit history

- **WHEN** the user edits a `.specificDates` budget's allocation from 1500.00 to 1800.00 and later to 2000.00
- **THEN** the store contains exactly one `AllocationChange` row whose `amount` is 2000.00; the prior figures (1500.00, 1800.00) are not retrievable (per F-2.08, latest-wins is the documented exception to the recurring forward-only rule)

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

The system SHALL provide `BudgetLifecycleService.resetBudget(_ budget: Budget, context: ModelContext, now: Date, weekStart: Weekday)` for the Reset Budget toolbar action. The `weekStart` parameter (no default; production callers pass `AppSettings.weekStartDay`) is threaded into the internal post-delete snapshot that decides whether a balancing `.resume` event is needed. The method SHALL:

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

### Requirement: Lifecycle write-paths surface save failure to the caller

Each `BudgetLifecycleService` write-path (`pauseBudget`, `resumeBudget`, the allocation-edit write-path, the manual-reset-carry-over write-path, and the reset-budget write-path) SHALL route its `context.save()` call through the shared persistence-save helper (operations `lifecycle_pause`, `lifecycle_resume`, `lifecycle_allocation_edit`, `lifecycle_reset_carry_over`, `lifecycle_reset_budget` respectively) rather than `try? context.save()`. Each method SHALL surface a thrown persistence error to its caller (e.g. by being marked `throws`); the existing eligibility-rejection return value (`Bool`) is preserved, so the method signatures become `throws -> Bool`. Eligibility rejection paths SHALL NOT attempt a save and SHALL NOT throw.

UI callers (Budget detail screen's Pause/Resume actions, Reset Budget, Reset Carry-Over, and any allocation-edit invocation from Add/Edit Budget) SHALL catch a thrown persistence error and present the standard save-error alert (see the `persistence-error-handling` capability) over the presenting screen. The accompanying analytics event for the action (e.g. `budget_paused`, `budget_resumed`, `budget_reset`, `carry_over_reset`) SHALL fire only on a successful save; on a thrown persistence error it SHALL NOT fire.

#### Scenario: Pause save failure surfaces the alert and does not fire budget_paused

- **WHEN** the user taps Pause on an eligible budget and the persistence-save helper throws
- **THEN** `pauseBudget` rethrows the persistence error, the save-error alert is presented over the Budget detail screen, no `budget_paused` analytics event fires, and Retry re-attempts the same pause-and-save

#### Scenario: Resume save failure surfaces the alert and does not fire budget_resumed

- **WHEN** the user taps Resume on an eligible budget and the persistence-save helper throws
- **THEN** `resumeBudget` rethrows the persistence error, the save-error alert is presented, no `budget_resumed` event fires, and Retry re-attempts the same resume-and-save

#### Scenario: Reset Budget save failure surfaces the alert and does not fire budget_reset

- **WHEN** the user confirms Reset Budget and the persistence-save helper throws
- **THEN** the reset-budget method rethrows the persistence error, the save-error alert is presented, no `budget_reset` event fires, and Retry re-attempts the same reset

#### Scenario: Reset Carry-Over save failure surfaces the alert and does not fire carry_over_reset

- **WHEN** the user confirms Reset Carry-Over and the persistence-save helper throws
- **THEN** the manual-reset-carry-over method rethrows the persistence error, the save-error alert is presented, no `carry_over_reset` event fires, and Retry re-attempts the same reset

#### Scenario: Eligibility rejection still returns false without throwing

- **WHEN** `pauseBudget` is called on a `.specificDates` budget, an already-paused budget, or a `.postEnd` budget
- **THEN** the method returns `false` without attempting a save and without throwing a persistence error

---

### Requirement: Background rollover persistence is best-effort

If `BudgetLifecycleService.result(for:)` (or any other read-driven entry point invoked from an eager lifecycle refresh) needs to persist rolled-over state, it SHALL route that save through the shared persistence-save helper (operation `lifecycle_rollover`). The helper logs and fires the `persistence_save_failed` analytics event on failure. The eager-refresh caller SHALL catch and swallow the thrown persistence error without presenting any UI; the rollover is retried by the next natural refresh.

#### Scenario: Background rollover save failure is silent on screen

- **WHEN** an eager lifecycle refresh attempts to persist rolled-over state and the persistence-save helper throws
- **THEN** a `Logger.persistence.error` line and a `persistence_save_failed` event are emitted AND no save-error alert is presented to the user

