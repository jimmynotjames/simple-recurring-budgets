## MODIFIED Requirements

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
