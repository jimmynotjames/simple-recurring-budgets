## ADDED Requirements

### Requirement: Period start computation

The system SHALL compute the start date of the budget period containing a given date, for all `BudgetPeriod` cases, respecting the user's configured week-start day and the budget's creation date as the biweekly anchor.

- **Daily**: The start of the calendar day containing the given date.
- **Weekly**: The most recent occurrence of the week-start day at or before the given date.
- **Biweekly**: The most recent biweekly boundary, where boundaries fall every 14 days from the anchor (the most recent week-start day at or before the budget's `createdAt`).
- **Monthly**: The first day of the calendar month containing the given date.

All date computations SHALL use the caller-provided `Calendar` instance (no implicit `Calendar.current`).

#### Scenario: Daily period start

- **WHEN** the date is 2026-04-15 14:30 UTC and the period is daily
- **THEN** the period start is 2026-04-15 00:00 in the calendar's time zone

#### Scenario: Weekly period start with Sunday week start

- **WHEN** the date is Wednesday 2026-04-15 and the period is weekly and week start is Sunday
- **THEN** the period start is Sunday 2026-04-12

#### Scenario: Weekly period start with Monday week start

- **WHEN** the date is Wednesday 2026-04-15 and the period is weekly and week start is Monday
- **THEN** the period start is Monday 2026-04-13

#### Scenario: Weekly period start on the week-start day itself

- **WHEN** the date is Sunday 2026-04-12 and the period is weekly and week start is Sunday
- **THEN** the period start is Sunday 2026-04-12 (same day)

#### Scenario: Biweekly period start

- **WHEN** the budget was created on Wednesday 2026-04-01, week start is Sunday, and the given date is Thursday 2026-04-17
- **THEN** the biweekly anchor is Sunday 2026-03-30 (most recent Sunday at or before 2026-04-01), and the current biweekly period start is Sunday 2026-04-13 (14 days after anchor)

#### Scenario: Monthly period start

- **WHEN** the date is 2026-04-15 and the period is monthly
- **THEN** the period start is 2026-04-01

### Requirement: Period end computation

The system SHALL compute the end date (exclusive) of the budget period containing a given date. The period end is the start of the next period.

#### Scenario: Daily period end

- **WHEN** the date is 2026-04-15 and the period is daily
- **THEN** the period end is 2026-04-16 00:00

#### Scenario: Weekly period end

- **WHEN** the date is Wednesday 2026-04-15 and the period is weekly and week start is Sunday
- **THEN** the period end is Sunday 2026-04-19

#### Scenario: Biweekly period end

- **WHEN** the biweekly period start is Sunday 2026-04-13
- **THEN** the period end is Sunday 2026-04-27 (14 days later)

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

The system SHALL compute the remaining amount for the current budget period as: `allocation − sum(expenses in current period)`. Only expenses whose date falls within the current period (>= period start, < period end) SHALL be counted. The result MAY be negative (overspending). This value is NOT adjusted by carry-over (per PRD §6.7).

#### Scenario: Under budget

- **WHEN** allocation is 20.00, period is daily, today's expenses total 12.50
- **THEN** remaining is 7.50

#### Scenario: Over budget

- **WHEN** allocation is 20.00, period is daily, today's expenses total 25.00
- **THEN** remaining is −5.00

#### Scenario: No expenses in current period

- **WHEN** allocation is 20.00, period is daily, and there are no expenses with today's date
- **THEN** remaining is 20.00

#### Scenario: Expenses from other periods are excluded

- **WHEN** allocation is 100.00, period is weekly (Sunday start), today is Wednesday, there are expenses of 30.00 on Monday and 50.00 from last Saturday
- **THEN** remaining is 70.00 (only the 30.00 Monday expense counts; Saturday is in the prior period)

#### Scenario: Add-funds transactions reduce expense total

- **WHEN** allocation is 20.00, period is daily, today has an expense of 15.00 and an add-funds transaction of −5.00 (negative amount per ExpenseItem convention)
- **THEN** remaining is 10.00 (net expenses = 15.00 + (−5.00) = 10.00; remaining = 20.00 − 10.00)

### Requirement: Carry-over roll

The system SHALL compute the updated carry-over amount by walking each completed period boundary since `carryOverLastProcessedDate`, and for each completed period folding in `(allocation − sum of expenses in that period)`. The result SHALL include the new cumulative carry-over amount and the date of the last completed period boundary (to be written back as `carryOverLastProcessedDate`).

Carry-over roll SHALL always execute regardless of whether carry-over display is enabled for the budget. The `isCarryOverEnabled` flag is a UI-layer display concern; the calculator always keeps the carry-over amount current so that toggling carry-over on at any time produces an immediately correct figure.

#### Scenario: Single period boundary crossed

- **WHEN** carry-over is 0.00, allocation is 20.00/day, last processed date is yesterday's start, yesterday's expenses total 18.00, and now is today
- **THEN** new carry-over is 2.00 (20.00 − 18.00), last processed date is today's start

#### Scenario: Multiple period boundaries crossed (app unopened for 3 days)

- **WHEN** carry-over is 0.00, allocation is 20.00/day, last processed date is 3 days ago, expenses are: day 1 = 25.00, day 2 = 15.00, day 3 = 20.00 (day 3 is yesterday, fully completed)
- **THEN** new carry-over is 0.00 (−5.00 + 5.00 + 0.00), last processed date is today's start

#### Scenario: No boundary crossed (same period)

- **WHEN** last processed date is within the current period and now is also within the current period
- **THEN** carry-over amount and last processed date are unchanged

#### Scenario: Negative carry-over accumulates

- **WHEN** carry-over is −10.00, allocation is 20.00/day, last processed is yesterday's start, yesterday's expenses total 30.00
- **THEN** new carry-over is −20.00 (−10.00 + (20.00 − 30.00)), last processed date is today's start

#### Scenario: Weekly carry-over roll

- **WHEN** carry-over is 0.00, allocation is 100.00/week, week start is Sunday, last processed date is last Sunday, this week's boundary has been crossed (it is now Sunday or later), last week's expenses total 80.00
- **THEN** new carry-over is 20.00, last processed date is this Sunday's start

### Requirement: Scheduled carry-over reset detection

The system SHALL determine whether a scheduled carry-over reset boundary has been crossed since `carryOverLastResetDate`, based on the budget's `resetCadence` and `BudgetPeriod`. Reset boundaries align to **period boundaries** (the first period boundary after the cadence interval has elapsed), never mid-period. Weekly reset boundaries SHALL respect the configured week-start day.

When a reset is detected, the result SHALL include the new reset date (the boundary at which the reset fires).

When `resetCadence` is `never`, the system SHALL always return no reset.

#### Scenario: Weekly reset cadence on a daily budget

- **WHEN** the budget period is daily, reset cadence is weekly, week start is Sunday, last reset date is Sunday 2026-04-05, and now is Sunday 2026-04-12 (or later, within that week)
- **THEN** a reset is detected with new reset date of Sunday 2026-04-12

#### Scenario: Monthly reset cadence on a weekly budget

- **WHEN** the budget period is weekly, reset cadence is monthly, week start is Monday, last reset date is 2026-03-03 (a Monday), and now is 2026-04-07 (the first Monday in April)
- **THEN** a reset is detected with new reset date of 2026-04-07

#### Scenario: Quarterly reset cadence on a monthly budget

- **WHEN** the budget period is monthly, reset cadence is quarterly, last reset date is 2026-01-01, and now is 2026-04-01
- **THEN** a reset is detected with new reset date of 2026-04-01

#### Scenario: Reset cadence is never

- **WHEN** the reset cadence is `never` and any amount of time has passed
- **THEN** no reset is detected

#### Scenario: Cadence interval not yet elapsed

- **WHEN** the budget period is daily, reset cadence is weekly, week start is Sunday, last reset date is Sunday 2026-04-05, and now is Thursday 2026-04-09
- **THEN** no reset is detected (the weekly cadence interval has not elapsed)

#### Scenario: Multiple reset cadences skipped (long gap)

- **WHEN** the budget period is daily, reset cadence is weekly, week start is Sunday, last reset date is Sunday 2026-03-01, and now is Sunday 2026-04-12
- **THEN** a reset is detected with new reset date being the most recent applicable Sunday boundary at or before now

### Requirement: Carry-over roll processes before reset check

The system SHALL ensure that carry-over rolling (folding completed periods) is processed before checking for a scheduled reset. This ensures that any accumulated carry-over from periods between the last processed date and the reset boundary is folded in before the reset zeros it out.

#### Scenario: Roll then reset in the same invocation

- **WHEN** carry-over is 0.00, allocation is 20.00/day, reset cadence is weekly, last processed date is 6 days ago (Saturday), last reset date is last Sunday, expenses over those 6 days total 100.00, and now is this Sunday (a new reset boundary)
- **THEN** carry-over first rolls to 20.00 (6 × 20.00 − 100.00), then the reset zeros it to 0.00 and updates the reset date to this Sunday
