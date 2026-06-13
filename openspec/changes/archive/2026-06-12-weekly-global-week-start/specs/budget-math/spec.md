# budget-math delta — weekly-global-week-start

## MODIFIED Requirements

### Requirement: Period start computation

The system SHALL compute the start date of the budget period containing a given date for every case of a `RecurringBudgetPeriod` wrapper enum (covering `daily`, `weekly`, `biweekly`, `monthly`). The wrapper enum SHALL make it a compile-time error to pass `BudgetPeriod.specificDates` into period-boundary math.

- **Daily**: The start of the calendar day containing the given date.
- **Weekly**: The most recent occurrence of the caller-provided global week-start day (`weekStart`, sourced from `AppSettings.weekStartDay` by production callers) at or before the given date.
- **Biweekly**: The most recent biweekly boundary, where boundaries fall every 14 days from the biweekly anchor (the budget's `startDate`). The `weekStart` parameter SHALL NOT influence biweekly boundaries — a weekday cannot determine which of two alternating weeks a 14-day cycle restarts in; the phase comes from the anchor date alone.
- **Monthly**: The first day of the calendar month containing the given date.

The weekly grid SHALL be global: every weekly budget shares the grid implied by `AppSettings.weekStartDay`, exactly as every monthly budget shares the calendar-month grid. `Budget.startDate` SHALL NOT influence the weekly grid; it defines only when the budget's window begins (and serves as the biweekly anchor). Changing `AppSettings.weekStartDay` therefore re-grids every weekly budget — past and future periods — on the next snapshot. (`AppSettings.weekStartDay` also continues to seed the pre-populated `startDate` for new weekly/biweekly budgets at creation time per the data-models capability.)

All date computations SHALL use the caller-provided `Calendar` instance (no implicit `Calendar.current`).

#### Scenario: Daily period start

- **WHEN** the date is 2026-04-15 14:30 UTC and the period is daily
- **THEN** the period start is 2026-04-15 00:00 in the calendar's time zone

#### Scenario: Weekly period start follows the global week-start day

- **WHEN** the date is Wednesday 2026-04-15, the period is weekly, and the caller passes `weekStart = .sunday`
- **THEN** the period start is Sunday 2026-04-12, regardless of the budget's `startDate` weekday

#### Scenario: Weekly budget started mid-week still uses the global grid

- **WHEN** the date is Friday 2026-04-17, the period is weekly, `Budget.startDate` is Wednesday 2026-04-01, and the caller passes `weekStart = .sunday`
- **THEN** the period start is Sunday 2026-04-12 — the budget's Wednesday `startDate` does not create a private Wed→Tue grid

#### Scenario: Weekly period start on the week-start day itself

- **WHEN** the date is Sunday 2026-04-12 and the caller passes `weekStart = .sunday`
- **THEN** the period start is Sunday 2026-04-12 (same day)

#### Scenario: Biweekly period start anchored on startDate

- **WHEN** `Budget.startDate` is Sunday 2026-03-29, the period is biweekly, and the given date is Thursday 2026-04-17
- **THEN** the biweekly anchor is Sunday 2026-03-29, and the current biweekly period start is Sunday 2026-04-12 (14 days after anchor), for every possible `weekStart` value

#### Scenario: Monthly period start

- **WHEN** the date is 2026-04-15 and the period is monthly
- **THEN** the period start is 2026-04-01

#### Scenario: SpecificDates does not reach PeriodCalculator

- **WHEN** application code attempts to pass `BudgetPeriod.specificDates` into period-boundary math
- **THEN** the call SHALL fail at compile time because `PeriodCalculator`'s public surface accepts `RecurringBudgetPeriod` only

### Requirement: BudgetCalculator.snapshot pure read entry point

The system SHALL provide a single pure read entry point `BudgetCalculator.snapshot(budget:expenses:now:calendar:weekStart:) -> BudgetSnapshot`. The function SHALL NOT mutate `Budget`, `ExpenseItem`, the `ModelContext`, or any other state. Every chip and computed display value SHALL be derived from the returned `BudgetSnapshot`.

`BudgetSnapshot` SHALL be a value type carrying at minimum:

- `remaining: Decimal` — current-period remaining (per "Remaining for current budget period"). During the pause-action period (a period that contains a `.pause` `LifecycleEvent`), `remaining` SHALL continue to compute as `allocation - in-period-expenses` per the math classifier (`isActive(...)` returns `true` for such periods). The UI presentation of this value is dimmed when `lifecycleState == .paused`, but the numeric value is the live "what would roll into carry-over at period close" amount.
- `carryOver: Decimal?` — cumulative carry-over from completed prior active periods, plus the current period's spillover when applicable (see "Asymmetric live coupling"). `nil` for `.specificDates` budgets (which hide the carry-over chip per PRD §6.7).
- `effectivePeriodStart: Date` — start of the current period (inclusive).
- `effectivePeriodEnd: Date` — start of the next period (exclusive).
- `effectiveAllocation: Decimal` — the allocation in effect at the current period's start.
- `lifecycleState` — one of `.preStart`, `.active`, `.paused`, `.postEnd`. The `.preStart` and `.postEnd` values are computed from `now` against `effectiveStartDate` / `effectiveEndExclusive`. The `.paused` value uses the moment-granular `isPausedAtMoment(now:sortedLifecycleEvents:)` classifier (see "Moment-granular UI pause classification") — distinct from the period-granular `isActive(period:lifecycleEvents:)` used by the carry-over walker.

All time-dependent inputs (`now`, `calendar`) SHALL be parameters. Production callers MAY use `Date()` and `Calendar.autoupdatingCurrent`; tests SHALL inject deterministic values.

The `weekStart: Weekday` parameter SHALL have **no default value** — every call site must choose explicitly, and production callers SHALL pass `AppSettings.weekStartDay`. The parameter governs only the weekly grid; daily, monthly, biweekly, and specificDates outputs SHALL be identical for every `weekStart` value. A weekly budget whose `startDate` falls mid-grid SHALL have its first period clipped at `startDate` (`effectivePeriodStart = max(currentPeriodStart, effectiveStartDate)`) with the full allocation awarded and no proration — the same convention as a monthly budget created mid-month.

#### Scenario: Snapshot is a pure read

- **WHEN** `BudgetCalculator.snapshot(...)` is invoked on a Budget
- **THEN** no field on the Budget, its ExpenseItems, or its AllocationChange / LifecycleEvent rows SHALL be mutated, and the ModelContext SHALL NOT be saved

#### Scenario: Snapshot returns active state for a recurring budget mid-period

- **WHEN** the budget is recurring, `now` is between `startDate` and any `endDate` (or `endDate` is nil), and there are no `LifecycleEvent` rows that would pause the current period
- **THEN** the returned `lifecycleState` is `.active`, `effectivePeriodStart` and `effectivePeriodEnd` bracket the current period, `effectiveAllocation` reflects the active allocation, and `carryOver` is non-nil

#### Scenario: Snapshot for a specificDates budget hides carry-over

- **WHEN** the budget's period is `.specificDates`
- **THEN** the returned `carryOver` SHALL be `nil`; `remaining = allocation − sumOfExpensesInWindow`; `effectivePeriodStart = startDate`, `effectivePeriodEnd = endDate + 1 day`

#### Scenario: The week-start setting controls a weekly budget's grid

- **WHEN** a weekly budget starts Wednesday 2026-04-01 with allocation 100 and the snapshot is taken Monday 2026-04-13
- **THEN** with `weekStart = .sunday` the current period starts 2026-04-12 and carry-over is 200 (partial week Apr 1–5 plus full week Apr 5–12, each at the full allocation); with `weekStart = .wednesday` the current period starts 2026-04-08 and carry-over is 100; with `weekStart = .monday` the current period starts 2026-04-13 and carry-over is 200

#### Scenario: Weekly mid-grid start clips the first period without proration

- **WHEN** a weekly budget starts Wednesday 2026-04-01 (allocation 100, `weekStart = .sunday`), has an expense of 15 dated 2026-03-30 (before `startDate`) and an expense of 30 dated 2026-04-02, and the snapshot is taken Sunday 2026-04-05
- **THEN** the pre-start expense is never counted, the partial first period [Apr 1, Apr 5) closes with contribution 100 − 30 = 70 (full allocation, no proration), `carryOver = 70`, and `remaining = 100`

#### Scenario: Biweekly output is independent of the week-start setting

- **WHEN** the same biweekly budget is snapshot at the same `now` with `weekStart = .sunday` and again with `weekStart = .friday`
- **THEN** `effectivePeriodStart`, `effectivePeriodEnd`, `remaining`, and `carryOver` are identical in both snapshots
