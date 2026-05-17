## Purpose

Specifies the pure budget math service layer (`PeriodCalculator` + `BudgetCalculator`) that computes period boundaries, remaining amounts, carry-over via a live walker, and snapshot output. All computation is stateless and has no SwiftData or SwiftUI dependencies.

## Requirements

### Requirement: Period start computation

The system SHALL compute the start date of the budget period containing a given date for every case of a `RecurringBudgetPeriod` wrapper enum (covering `daily`, `weekly`, `biweekly`, `monthly`). The wrapper enum SHALL make it a compile-time error to pass `BudgetPeriod.specificDates` into period-boundary math.

- **Daily**: The start of the calendar day containing the given date.
- **Weekly**: The most recent occurrence of the budget's weekly anchor day at or before the given date.
- **Biweekly**: The most recent biweekly boundary, where boundaries fall every 14 days from the biweekly anchor (the most recent weekly anchor day at or before the budget's `startDate`).
- **Monthly**: The first day of the calendar month containing the given date.

For weekly and biweekly periods, the weekly anchor SHALL be derived from `Budget.startDate.weekday`. The global `AppSettings.weekStartDay` SHALL NOT be consulted at math-time for any budget with a populated `startDate`. (`AppSettings.weekStartDay` continues to seed the pre-populated `startDate` at budget creation time per the data-models capability.)

All date computations SHALL use the caller-provided `Calendar` instance (no implicit `Calendar.current`).

#### Scenario: Daily period start

- **WHEN** the date is 2026-04-15 14:30 UTC and the period is daily
- **THEN** the period start is 2026-04-15 00:00 in the calendar's time zone

#### Scenario: Weekly period start anchored on Sunday startDate

- **WHEN** the date is Wednesday 2026-04-15, the period is weekly, and `Budget.startDate` is a Sunday
- **THEN** the period start is Sunday 2026-04-12 (and `AppSettings.weekStartDay` is not consulted)

#### Scenario: Weekly period start anchored on Wednesday startDate

- **WHEN** the date is Friday 2026-04-17, the period is weekly, and `Budget.startDate` is Wednesday 2026-04-01
- **THEN** the period start is Wednesday 2026-04-15 (per-budget anchor; AppSettings.weekStartDay is irrelevant)

#### Scenario: Weekly period start on the anchor day itself

- **WHEN** the date is Sunday 2026-04-12 and `Budget.startDate` is a Sunday
- **THEN** the period start is Sunday 2026-04-12 (same day)

#### Scenario: Biweekly period start anchored on startDate

- **WHEN** `Budget.startDate` is Sunday 2026-03-29, the period is biweekly, and the given date is Thursday 2026-04-17
- **THEN** the biweekly anchor is Sunday 2026-03-29, and the current biweekly period start is Sunday 2026-04-12 (14 days after anchor)

#### Scenario: Monthly period start

- **WHEN** the date is 2026-04-15 and the period is monthly
- **THEN** the period start is 2026-04-01

#### Scenario: SpecificDates does not reach PeriodCalculator

- **WHEN** application code attempts to pass `BudgetPeriod.specificDates` into period-boundary math
- **THEN** the call SHALL fail at compile time because `PeriodCalculator`'s public surface accepts `RecurringBudgetPeriod` only

### Requirement: Period end computation

The system SHALL compute the end date (exclusive) of the budget period containing a given date. The period end is the start of the next period.

#### Scenario: Daily period end

- **WHEN** the date is 2026-04-15 and the period is daily
- **THEN** the period end is 2026-04-16 00:00

#### Scenario: Weekly period end

- **WHEN** the date is Wednesday 2026-04-15 and the period is weekly and week start is Sunday
- **THEN** the period end is Sunday 2026-04-19

#### Scenario: Biweekly period end

- **WHEN** the biweekly period start is Sunday 2026-04-12
- **THEN** the period end is Sunday 2026-04-26 (14 days later)

#### Scenario: Monthly period end

- **WHEN** the date is 2026-04-15 and the period is monthly
- **THEN** the period end is 2026-05-01

### Requirement: Period boundary enumeration

The system SHALL enumerate all period boundary dates between two dates (inclusive of start, exclusive of end). This powers the multi-period catch-up walk for carry-over rolling.

#### Scenario: Daily boundaries over a 3-day gap

- **WHEN** the start date is 2026-04-12 00:00 and the end date is 2026-04-15 00:00 and the period is daily
- **THEN** the boundaries returned are [2026-04-12, 2026-04-13, 2026-04-14] (three boundaries, each a day start)

#### Scenario: Weekly boundaries spanning three weeks

- **WHEN** the start date is 2026-04-05 (a Sunday) and the end date is 2026-04-20 and the period is weekly and week start is Sunday
- **THEN** the boundaries returned are [2026-04-05, 2026-04-12, 2026-04-19]

#### Scenario: No boundaries when start equals end

- **WHEN** the start and end dates are both 2026-04-12 00:00
- **THEN** the boundaries returned are empty

#### Scenario: Monthly boundaries across quarter

- **WHEN** the start date is 2026-01-01 and the end date is 2026-04-01 and the period is monthly
- **THEN** the boundaries are [2026-01-01, 2026-02-01, 2026-03-01]

### Requirement: Remaining for current budget period

The system SHALL compute the remaining amount for the current budget period as: `effectiveAllocation − sum(expenses in current period)`, where `effectiveAllocation` is the allocation in effect at the start of the current period (per `allocationInEffect`). Only expenses whose date falls within the current period (>= period start, < period end) SHALL be counted. The result MAY be negative (overspending). This value is NOT adjusted by carry-over (per PRD §6.7). For `.specificDates` budgets, "current period" is the entire `[startDate, endDate]` window.

#### Scenario: Under budget

- **WHEN** `effectiveAllocation` is 20.00, period is daily, today's expenses total 12.50
- **THEN** remaining is 7.50

#### Scenario: Over budget

- **WHEN** `effectiveAllocation` is 20.00, period is daily, today's expenses total 25.00
- **THEN** remaining is −5.00

#### Scenario: No expenses in current period

- **WHEN** `effectiveAllocation` is 20.00, period is daily, and there are no expenses with today's date
- **THEN** remaining is 20.00

#### Scenario: Expenses from other periods are excluded

- **WHEN** `effectiveAllocation` is 100.00, period is weekly, today is Wednesday inside week 04-12 to 04-19, there are expenses of 30.00 on Monday and 50.00 from last Saturday
- **THEN** remaining is 70.00 (only the Monday expense counts)

#### Scenario: Add-funds transactions reduce expense total

- **WHEN** `effectiveAllocation` is 20.00, period is daily, today has an expense of 15.00 and an add-funds transaction of −5.00
- **THEN** remaining is 10.00 (net expenses = 10.00; remaining = 20.00 − 10.00)

#### Scenario: Edited allocation uses the value in effect at this period's start

- **WHEN** the budget has two `AllocationChange` rows — one at the budget's `startDate` with amount 20.00 and one at the current period's start with amount 25.00 — and today's expenses total 5.00
- **THEN** remaining is 20.00 (25.00 − 5.00); the value 20.00 from the prior period is not consulted for the current period

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

### Requirement: Date normalization helpers

The system SHALL provide derived values `effectiveStartDate`, `effectiveEndInclusive`, and `effectiveEndExclusive` consumed by the snapshot:

- `effectiveStartDate`: `Budget.startDate` if non-nil; otherwise `Budget.createdAt`. This is a safety-net fallback for malformed sync records — UI flows SHALL always populate `startDate` at save time per the data-models capability.
- `effectiveEndInclusive`: `Budget.endDate` if non-nil; otherwise nil (recurring budget runs indefinitely).
- `effectiveEndExclusive`: `effectiveEndInclusive + 1 second` (start-of-day-aligned `endDate` is treated as the inclusive last day, per algorithm doc §A.4.0).

The walker and current-period helpers SHALL never inspect `Budget.startDate` or `Budget.endDate` directly — they MUST go through these derived values so the fallback rule is honored uniformly.

#### Scenario: Nil startDate falls back to createdAt

- **WHEN** a Budget has `startDate = nil` and `createdAt = 2026-04-01 10:00`
- **THEN** `effectiveStartDate` is 2026-04-01 10:00

#### Scenario: Populated startDate is honored

- **WHEN** a Budget has `startDate = 2026-04-12 00:00` and `createdAt = 2026-04-15 10:00`
- **THEN** `effectiveStartDate` is 2026-04-12 00:00 (not the later createdAt)

### Requirement: allocationInEffect helper

The system SHALL provide `allocationInEffect(at date: Date, history: [AllocationChange]) -> Decimal` that returns the allocation in effect at the given instant. The result SHALL be the `amount` of the latest `AllocationChange` whose `effectiveFrom <= date`, breaking ties by `lastModified` (later wins). If no row satisfies the predicate, the helper SHALL return the earliest `AllocationChange.amount` as a defensive fallback (this fallback is never reached in normal flow because every saved budget has an initial row at `startDate`).

#### Scenario: Latest applicable AllocationChange wins

- **WHEN** the history is `[(effectiveFrom: 2026-03-01, amount: 20.00), (effectiveFrom: 2026-04-01, amount: 25.00)]` and the query date is 2026-04-15
- **THEN** the result is 25.00

#### Scenario: Earlier history when query precedes all changes

- **WHEN** the history is `[(effectiveFrom: 2026-04-01, amount: 25.00)]` and the query date is 2026-03-15
- **THEN** the result is 25.00 (defensive fallback to the earliest row's amount)

#### Scenario: Tie broken by lastModified

- **WHEN** two AllocationChange rows share the same `effectiveFrom = 2026-04-01` but differ in `lastModified` (one earlier, one later) with amounts 20.00 and 25.00 respectively
- **THEN** the result for any date on/after 2026-04-01 is 25.00 (the row with the later `lastModified`)

### Requirement: Carry-over walker

The system SHALL provide a `walkCarryOver(...)` helper that returns the cumulative carry-over from every completed active period in the walk window. The walk window SHALL start at `max(effectiveStartDate, Budget.lastResetDate ?? .distantPast)` and end at the start of the current in-progress period. For each completed period:

1. Classify the period as active or paused via `isActive(period:lifecycleEvents:)`.
2. If paused, contribute 0.
3. If active, contribute `allocationInEffect(at: periodStart, history:) − sum(expenses with date in [periodStart, periodEnd))`.

Backdated expense edits that fall into a prior completed period SHALL be folded into that period's contribution on the next call (the walker re-evaluates every period on every read).

#### Scenario: Single completed period folded in

- **WHEN** carry-over is being computed for a daily budget with allocation 20.00, current period starts today, the prior day's expenses total 18.00, no resets, no pause events
- **THEN** the walker returns 2.00

#### Scenario: Multiple completed periods catch up

- **WHEN** the prior three days have expenses totaling 25.00, 15.00, and 20.00 with allocation 20.00/day, no resets, no pause events
- **THEN** the walker returns 0.00 (−5.00 + 5.00 + 0.00)

#### Scenario: lastResetDate trims the walk window

- **WHEN** the budget has `lastResetDate = 2026-04-10 00:00` and there are completed daily periods before and after that date
- **THEN** only periods whose end is strictly after 2026-04-10 contribute to the walker's sum

#### Scenario: Backdated expense recomputes a prior period

- **WHEN** the walker is called with two completed daily periods (yesterday and the day before) and a new $30 expense is backdated to two days ago
- **THEN** the walker reflects the new total for that prior period in its return value on the next call (no boundary handshake needed)

#### Scenario: Paused periods contribute 0 regardless of allocation

- **WHEN** a completed period falls in a paused interval per the lifecycle events
- **THEN** that period contributes 0 to the walker's sum, even if expenses or allocation history exist for it

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

### Requirement: Asymmetric live coupling for the current period

The system SHALL implement `currentPeriodSpillover` to absorb the current in-progress period's committed overflow into the carry-over chip in real time (algorithm doc §A.5.6):

- If `remaining` is inside `[0, effectiveAllocation]` (ordinary mid-period state), spillover is 0 — the current period's slack stays in "today's envelope" until the period closes.
- If `remaining < 0` (overspend), spillover is `remaining` (negative). The carry-over decreases by the overshoot immediately.
- If `remaining > effectiveAllocation` (the user added negative-amount expenses per F-6.01 so net spend went below 0), spillover is `remaining − effectiveAllocation` (positive). The carry-over increases by the excess immediately.

The snapshot's `carryOver` (for recurring budgets) SHALL equal `walkCarryOver(...) + currentPeriodSpillover`.

In `.postEnd` state the rule collapses to symmetric: the entire final-period remaining (positive or negative) is added to the carry-over, since there is no future period close.

#### Scenario: Ordinary slack does not affect carry-over

- **WHEN** `effectiveAllocation = 20`, today's expenses total 10, prior walker sum = 5
- **THEN** `currentPeriodSpillover = 0` and the chip reads carry-over = 5

#### Scenario: Overspend lands live

- **WHEN** `effectiveAllocation = 20`, today's expenses total 21 (so remaining = −1), prior walker sum = 5
- **THEN** `currentPeriodSpillover = −1` and the chip reads carry-over = 4

#### Scenario: Add-funds excess lands live

- **WHEN** `effectiveAllocation = 20`, today has a −$30 add-funds row (so remaining = 50), prior walker sum = 5
- **THEN** `currentPeriodSpillover = 30` (50 − 20) and the chip reads carry-over = 35

#### Scenario: Reverting the committed action snaps carry-over back

- **WHEN** the user deletes the $21 expense from the overspend scenario above
- **THEN** the next snapshot returns `currentPeriodSpillover = 0` and the chip reads carry-over = 5

#### Scenario: PostEnd collapses to symmetric

- **WHEN** `lifecycleState = .postEnd`, the final period's remaining is +12, and the walker sum from earlier periods is 8
- **THEN** the snapshot's `carryOver` is 20 (8 + 12), independent of whether the final period's remaining is inside `[0, effectiveAllocation]`

### Requirement: SpecificDates snapshot branch

The system SHALL handle `BudgetPeriod.specificDates` budgets through a dedicated branch in `BudgetCalculator.snapshot(...)` (algorithm doc §A.4.2). The branch SHALL:

- Treat the entire `[startDate, endDate]` window as a single period.
- Compute `remaining = effectiveAllocation − sumOfExpensesInWindow`, where `effectiveAllocation` is the latest `AllocationChange` by `(effectiveFrom, lastModified)`.
- Return `carryOver = nil` so the UI knows to hide the carry-over chip.
- Freeze the snapshot's `remaining` and `lifecycleState = .postEnd` once `now > endDate`.

The branch SHALL ignore `isCarryOverEnabled` and `LifecycleEvent` rows of any kind. If such rows are encountered (e.g., from a CloudKit divergence or a UI bug), they SHALL be treated as no-ops, not as errors.

#### Scenario: SpecificDates in-progress

- **WHEN** the period is `.specificDates`, the window is 2026-04-01..2026-04-30, allocation is 350, expenses in the window total 120, and now is 2026-04-15
- **THEN** `remaining = 230`, `carryOver = nil`, `lifecycleState = .active`

#### Scenario: SpecificDates past endDate

- **WHEN** the period is `.specificDates`, `endDate = 2026-04-30`, now is 2026-05-15
- **THEN** `lifecycleState = .postEnd`, `remaining` is the frozen final tally

#### Scenario: SpecificDates ignores spurious pause events

- **WHEN** a `LifecycleEvent` with `kind = .pause` somehow exists on a `.specificDates` budget
- **THEN** the snapshot's behavior is identical to the case where no LifecycleEvent rows exist
