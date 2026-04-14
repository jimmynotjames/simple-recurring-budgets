## 1. Result Types

- [ ] 1.1 Create `CarryOverRollResult` and `ResetCheckResult` structs in `Domain/BudgetCalculator.swift` (or a dedicated file). `CarryOverRollResult` has `amount: Decimal` + `lastProcessedDate: Date`. `ResetCheckResult` has `shouldReset: Bool` + `newResetDate: Date?`.

## 2. PeriodCalculator — Implementation

- [ ] 2.1 Create `Domain/PeriodCalculator.swift` with `periodStart(containing:period:weekStart:biweeklyAnchor:calendar:) -> Date` covering daily, weekly, biweekly, and monthly cases.
- [ ] 2.2 Add `periodEnd(containing:period:weekStart:biweeklyAnchor:calendar:) -> Date` — returns the start of the next period.
- [ ] 2.3 Add `periodBoundaries(from:to:period:weekStart:biweeklyAnchor:calendar:) -> [Date]` — enumerates all boundary dates from start (inclusive) to end (exclusive).

## 3. PeriodCalculator — Tests

- [ ] 3.1 Create `simple-recurring-budgetsTests/Domain/PeriodCalculatorTests.swift` with a fixed-timezone `Calendar` helper.
- [ ] 3.2 Test `periodStart` for daily (time-of-day strips to midnight).
- [ ] 3.3 Test `periodStart` for weekly with Sunday and Monday week starts, including when the date falls on the week-start day itself.
- [ ] 3.4 Test `periodStart` for biweekly — verify anchor derivation from `createdAt` and correct 14-day cycle alignment.
- [ ] 3.5 Test `periodStart` for monthly.
- [ ] 3.6 Test `periodEnd` for all four period types.
- [ ] 3.7 Test `periodBoundaries` — multi-day gap (daily), multi-week gap (weekly), empty result when start == end, monthly across quarter boundary.

## 4. BudgetCalculator — Remaining

- [ ] 4.1 Create `Domain/BudgetCalculator.swift` with `remaining(allocation:expenses:periodStart:periodEnd:) -> Decimal` — filters expenses by date range, sums amounts, subtracts from allocation.

## 5. BudgetCalculator — Carry-Over Roll

- [ ] 5.1 Add `rollCarryOver(currentAmount:allocation:expenses:lastProcessedDate:now:period:weekStart:biweeklyAnchor:calendar:) -> CarryOverRollResult` — walks each completed period boundary from `lastProcessedDate` to `now` using `PeriodCalculator.periodBoundaries`, folds `(allocation − period expenses)` per period. Always computes regardless of `isCarryOverEnabled` (display-only flag). Returns unchanged values when no boundary was crossed.

## 6. BudgetCalculator — Scheduled Reset

- [ ] 6.1 Add `checkScheduledReset(lastResetDate:resetCadence:now:period:weekStart:biweeklyAnchor:calendar:) -> ResetCheckResult` — determines if a reset cadence boundary has been crossed since `lastResetDate`. Handles weekly/biweekly/monthly/quarterly cadences aligned to period boundaries. Returns no-reset for `never`.

## 7. BudgetCalculator — Tests

- [ ] 7.1 Create `simple-recurring-budgetsTests/Domain/BudgetCalculatorTests.swift` with test helpers (fixed calendar, in-memory `ModelContainer` for `ExpenseItem` creation).
- [ ] 7.2 Test `remaining` — under budget, over budget, no expenses, expenses from other periods excluded, add-funds transactions.
- [ ] 7.3 Test `rollCarryOver` — single boundary, multi-boundary catch-up (3-day gap), no boundary crossed, negative carry-over accumulation.
- [ ] 7.4 Test `rollCarryOver` for weekly period — verifies correct expense bucketing across week boundaries.
- [ ] 7.5 Test `checkScheduledReset` — weekly cadence on daily budget, monthly cadence on weekly budget, quarterly cadence on monthly budget, `never` cadence, cadence not yet elapsed, long gap (multiple resets skipped returns most recent boundary).
- [ ] 7.6 Test roll-then-reset ordering — carry-over accumulates from completed periods and then resets in the same invocation.

## 8. Documentation

- [ ] 8.1 Update `docs/tech-design-doc.md` — add a section documenting the `PeriodCalculator` / `BudgetCalculator` service layer: where the files live, public API summary, biweekly anchor convention, and how ViewModels will consume the calculator.
