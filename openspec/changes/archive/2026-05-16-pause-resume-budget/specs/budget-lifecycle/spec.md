## ADDED Requirements

### Requirement: Pause budget write-path

The system SHALL provide `BudgetLifecycleService.pauseBudget(_ budget: Budget, context: ModelContext, now: Date) -> Bool` for the Pause Budget action. The method SHALL implement the eligibility, clamping, and write rules below.

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

The system SHALL provide `BudgetLifecycleService.resumeBudget(_ budget: Budget, context: ModelContext, now: Date) -> Bool` for the Resume Budget action. The method SHALL implement the eligibility and write rules below.

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

### Requirement: Pause and resume produce period-granular semantics via the existing algorithm

The pause and resume write paths SHALL produce `LifecycleEvent` rows that the existing `LifecycleClassification.isActive(period:lifecycleEvents:)` consumes per the period-granular rules already shipped:

- The period containing a `.pause` event remains active (the snapshot continues to compute carry-over normally for that period).
- Every period strictly after a `.pause` event and strictly before the next `.resume` event is paused; paused periods contribute 0 to the carry-over walk.
- The period containing a `.resume` event is fully active (no proration).

The pause/resume write paths SHALL NOT introduce any classification logic of their own; their only responsibility is to insert the correct event row.

#### Scenario: Pause-action period is still active

- **WHEN** the user pauses a daily budget mid-day and the snapshot is computed at the end of that same day
- **THEN** the pause-action day's carry-over contribution is computed normally (`allocationInEffect - sum(expenses)`), per `LifecycleClassification.isActive(period:lifecycleEvents:)`

#### Scenario: Period immediately after the pause-action period is paused

- **WHEN** the user pauses a daily budget on day D and the snapshot is computed on day D+1 with no intervening resume
- **THEN** day D+1's carry-over contribution is 0

#### Scenario: Resume-action period is fully active

- **WHEN** the user resumes a daily budget at any moment during day R
- **THEN** day R contributes a full day's allocation to the carry-over walk (no proration)

## MODIFIED Requirements

### Requirement: BudgetLifecycleResult returned for display

The system SHALL return a `BudgetLifecycleResult` value with the following fields, populated from the underlying `BudgetSnapshot`:

- `remaining: Decimal` ← `snapshot.remaining`.
- `carryOverAmount: Decimal` ← `snapshot.carryOver ?? 0`. The `?? 0` flattens the `nil` that `BudgetCalculator.snapshot` returns for `.specificDates` budgets. Per F-2.08, the carry-over chip is **hidden** for specificDates budgets (chip-hiding work lives in `BudgetDetailView` / `BudgetRowView` and ships with the F-2.08 UI). Until F-2.08 ships, this fallback is unreachable in normal flow. The F-2.08 change MUST either (a) stop calling `result(for:)` for specificDates budgets, or (b) replace `BudgetLifecycleResult` with a sum type that preserves the `nil`.
- `periodStart: Date` ← `snapshot.effectivePeriodStart`.
- `periodEnd: Date` ← `snapshot.effectivePeriodEnd`.
- `lifecycleState: BudgetLifecycleState` ← `snapshot.lifecycleState`. Used by view sites to switch between the active, paused, pre-start, and post-end presentations.
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
