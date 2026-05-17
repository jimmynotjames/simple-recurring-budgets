## ADDED Requirements

### Requirement: Moment-granular UI pause classification

The system SHALL provide a moment-granular pause classifier used to populate `BudgetSnapshot.lifecycleState` for view-layer consumption. The classifier SHALL be distinct from the period-granular `isActive(period:lifecycleEvents:)` used by the carry-over walker — the math half of the algorithm remains period-granular and is NOT changed by this requirement.

The classifier SHALL be a pure function with the contract `isPausedAtMoment(now:sortedLifecycleEvents:) -> Bool`:

- It SHALL return `true` iff the most recent `LifecycleEvent` whose `effectiveDate < now` (strict less-than) has `kind == .pause`.
- It SHALL return `false` when the most recent such event has `kind == .resume`, when no event satisfies `effectiveDate < now`, or when `sortedLifecycleEvents` is empty.
- It SHALL operate on `sortedLifecycleEvents` pre-sorted ascending by `(effectiveDate, lastModified)` — matching the contract of `isActive(...)` so the snapshot can reuse the same sorted array for both classifiers.
- The strict less-than boundary means a pause event at the exact moment `now` does NOT yet flip the UI to paused — the transition happens at the next instant. This aligns with the period-granular math classifier (which treats the pause-action period as itself active) and preserves the date-picker upper bound (`pauseEffectiveDate`) as a valid date for new entries. In production, `now` is always strictly greater than any just-recorded `effectiveDate` (snapshot's `Date()` runs strictly after the service's), so the strict boundary is observationally equivalent to `<=`.

`BudgetSnapshot.lifecycleState` SHALL derive from this classifier together with the pre-existing `.preStart` / `.postEnd` rules, in the following precedence:

1. If `now >= effectiveEndExclusive` and `budget.endDate != nil` → `.postEnd`.
2. Else if `now < effectiveStartDate` → `.preStart`.
3. Else if `isPausedAtMoment(now:sortedLifecycleEvents:)` returns `true` → `.paused`.
4. Else → `.active`.

The `.postEnd` and `.preStart` precedence over `.paused` implements F-7.06's "Pause before `startDate`: the pre-start chip presentation is preserved until `startDate`" and F-7.07's terminal-endDate rule.

#### Scenario: Mid-period pause flips lifecycleState immediately

- **WHEN** a daily budget has `startDate = 2026-04-01`, a single `LifecycleEvent(kind: .pause, effectiveDate: 2026-04-10 14:00)`, and `now = 2026-04-10 14:01` (one minute after the pause)
- **THEN** `BudgetSnapshot.lifecycleState == .paused`

#### Scenario: Mid-period pause does not change carry-over math for the pause-action period

- **WHEN** a daily budget has `startDate = 2026-04-01`, allocation 20.00, a single `LifecycleEvent(kind: .pause, effectiveDate: 2026-04-10 14:00)`, expenses totaling 12.00 on 2026-04-10 before the pause, and the snapshot is computed at the end of 2026-04-10 (or later, when the period closes)
- **THEN** the pause-action day contributes `20.00 - 12.00 = 8.00` to the carry-over walker (the math classifier — `isActive(...)` — still returns `true` for the period that contains the `.pause` event, per the "Lifecycle classification" requirement)

#### Scenario: Resume in the same period flips lifecycleState back

- **WHEN** the budget's lifecycle history is `[(.pause, 2026-04-10 09:00), (.resume, 2026-04-10 11:00)]` and `now = 2026-04-10 12:00`
- **THEN** `BudgetSnapshot.lifecycleState == .active` (the most-recent event strictly before now is the resume)

#### Scenario: Pre-start precedence is preserved

- **WHEN** the budget has `startDate = 2026-05-01`, a `LifecycleEvent(kind: .pause, effectiveDate: 2026-04-10)` (clamped to startDate by the write path or set directly), and `now = 2026-04-20` (before startDate)
- **THEN** `BudgetSnapshot.lifecycleState == .preStart` (pre-start wins over paused while `now < startDate`)

#### Scenario: Post-end precedence is preserved

- **WHEN** the budget has `endDate = 2026-04-30`, a `.pause` event on 2026-04-25, and `now = 2026-05-05`
- **THEN** `BudgetSnapshot.lifecycleState == .postEnd` (post-end wins over paused)

#### Scenario: Empty lifecycle history is active

- **WHEN** the budget has no `LifecycleEvent` rows and `now` is between `startDate` and any `endDate`
- **THEN** `isPausedAtMoment(...)` returns `false` and `BudgetSnapshot.lifecycleState == .active`

## MODIFIED Requirements

### Requirement: BudgetCalculator.snapshot pure read entry point

The system SHALL provide a single pure read entry point `BudgetCalculator.snapshot(budget:expenses:now:calendar:) -> BudgetSnapshot`. The function SHALL NOT mutate `Budget`, `ExpenseItem`, the `ModelContext`, or any other state. Every chip and computed display value SHALL be derived from the returned `BudgetSnapshot`.

`BudgetSnapshot` SHALL be a value type carrying at minimum:

- `remaining: Decimal` — current-period remaining (per "Remaining for current budget period"). During the pause-action period (a period that contains a `.pause` `LifecycleEvent`), `remaining` SHALL continue to compute as `allocation - in-period-expenses` per the math classifier (`isActive(...)` returns `true` for such periods). The UI presentation of this value is dimmed when `lifecycleState == .paused`, but the numeric value is the live "what would roll into carry-over at period close" amount.
- `carryOver: Decimal?` — cumulative carry-over from completed prior active periods, plus the current period's spillover when applicable (see "Asymmetric live coupling"). `nil` for `.specificDates` budgets (which hide the carry-over chip per PRD §6.7).
- `effectivePeriodStart: Date` — start of the current period (inclusive).
- `effectivePeriodEnd: Date` — start of the next period (exclusive).
- `effectiveAllocation: Decimal` — the allocation in effect at the current period's start.
- `lifecycleState` — one of `.preStart`, `.active`, `.paused`, `.postEnd`. The `.preStart` and `.postEnd` values are computed from `now` against `effectiveStartDate` / `effectiveEndExclusive`. The `.paused` value uses the moment-granular `isPausedAtMoment(now:sortedLifecycleEvents:)` classifier (see "Moment-granular UI pause classification") — distinct from the period-granular `isActive(period:lifecycleEvents:)` used by the carry-over walker.

All time-dependent inputs (`now`, `calendar`) SHALL be parameters. Production callers MAY use `Date()` and `Calendar.autoupdatingCurrent`; tests SHALL inject deterministic values.

#### Scenario: Snapshot is a pure read

- **WHEN** `BudgetCalculator.snapshot(...)` is invoked on a Budget
- **THEN** no field on the Budget, its ExpenseItems, or its AllocationChange / LifecycleEvent rows SHALL be mutated, and the ModelContext SHALL NOT be saved

#### Scenario: Snapshot returns active state for a recurring budget mid-period

- **WHEN** the budget is recurring, `now` is between `startDate` and any `endDate` (or `endDate` is nil), and there are no `LifecycleEvent` rows that would pause the current period
- **THEN** the returned `lifecycleState` is `.active`, `effectivePeriodStart` and `effectivePeriodEnd` bracket the current period, `effectiveAllocation` reflects the active allocation, and `carryOver` is non-nil

#### Scenario: Snapshot for a specificDates budget hides carry-over

- **WHEN** the budget's period is `.specificDates`
- **THEN** the returned `carryOver` SHALL be `nil`; `remaining = allocation − sumOfExpensesInWindow`; `effectivePeriodStart = startDate`, `effectivePeriodEnd = endDate + 1 day`

### Requirement: Lifecycle classification

The system SHALL provide `isActive(period:lifecycleEvents:) -> Bool` that returns whether a given completed period was active or paused **for carry-over math**. This is the period-granular classifier consumed by `walkCarryOver(...)` and by the `remaining = 0` short-circuit for periods that fall entirely inside a paused interval. Pause and Resume `LifecycleEvent` rows operate at whole-period granularity for the math (algorithm doc §A.5.4):

- The period containing a Pause event is itself active for math (carry-over is calculated normally for that period).
- Every period strictly after a Pause and strictly before the next Resume is paused for math (contributes 0 to the walker).
- The period containing a Resume event is active in full for math (no proration).

A budget with no `LifecycleEvent` rows SHALL be treated as fully active from `startDate` onward.

This requirement governs the math half of the lifecycle algorithm only. The UI half — what `BudgetSnapshot.lifecycleState` returns to view sites — is governed by the separate "Moment-granular UI pause classification" requirement. The two classifiers SHALL coexist inside `BudgetCalculator.snapshot(...)` without affecting each other.

#### Scenario: Pause action period is active for math

- **WHEN** a Pause event lands on 2026-04-15 for a daily budget, and the queried period is the day 2026-04-15
- **THEN** `isActive` returns `true` for that period (and the walker's carry-over contribution for that period is computed normally as `allocation - in-period-expenses`)

#### Scenario: Period after the pause action is paused for math

- **WHEN** the queried period is the day 2026-04-16 (the day after the Pause event with no intervening Resume)
- **THEN** `isActive` returns `false` (and the walker's contribution for that period is 0)

#### Scenario: Resume action period is active for math

- **WHEN** a Resume event lands on 2026-04-20 and the queried period is the day 2026-04-20
- **THEN** `isActive` returns `true` (the walker contributes a full period's allocation, no proration)
