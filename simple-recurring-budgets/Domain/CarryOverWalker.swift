import Foundation

/// Returns cumulative carry-over from every completed active period in `[walkWindowStart, currentPeriodStart)`.
/// Active periods contribute `allocationInEffect − sum(expenses in period)`; paused periods contribute 0.
///
/// Expenses are filtered from `max(boundaryStart, walkWindowStart)`, so the period containing
/// `walkWindowStart` (e.g. a Reset Carry-Over) ignores pre-reset expenses while still awarding the full
/// allocation (no proration), even when the budget started or was reset mid-period.
///
/// Pure function that re-evaluates every period on each call, so backdated expenses fold in automatically.
///
/// **Contract:** `sortedAllocationChanges` and `sortedLifecycleEvents` must be pre-sorted ascending by
/// `(effectiveFrom, lastModified)` and `(effectiveDate, lastModified)`; `BudgetCalculator.snapshot` sorts
/// once to avoid a log factor per iteration.
func walkCarryOver(
  from walkWindowStart: Date,
  to currentPeriodStart: Date,
  period: RecurringBudgetPeriod,
  weekStart: Weekday,
  biweeklyAnchor: Date,
  sortedAllocationChanges: [AllocationChange],
  sortedLifecycleEvents: [LifecycleEvent],
  expenses: [ExpenseItem],
  calendar: Calendar
) -> Decimal {
  let boundaries = PeriodCalculator.periodBoundaries(
    from: walkWindowStart,
    to: currentPeriodStart,
    period: period,
    weekStart: weekStart,
    biweeklyAnchor: biweeklyAnchor,
    calendar: calendar
  )

  var sum: Decimal = 0

  for (i, boundaryStart) in boundaries.enumerated() {
    let nextBoundary: Date = if i + 1 < boundaries.count {
      boundaries[i + 1]
    } else {
      PeriodCalculator.periodEnd(
        containing: boundaryStart,
        period: period,
        weekStart: weekStart,
        biweeklyAnchor: biweeklyAnchor,
        calendar: calendar
      )
    }

    guard nextBoundary <= currentPeriodStart else { break }

    guard isActive(
      periodStart: boundaryStart,
      periodEnd: nextBoundary,
      sortedLifecycleEvents: sortedLifecycleEvents
    ) else { continue }

    let allocation = allocationInEffect(at: boundaryStart, sortedHistory: sortedAllocationChanges)
    let expenseLowerBound = max(boundaryStart, walkWindowStart)
    let periodExpenses = expenses.filter { $0.date >= expenseLowerBound && $0.date < nextBoundary }
    let contribution = allocation - periodExpenses.reduce(Decimal(0)) { $0 + $1.amount }
    sum += contribution
  }

  return sum
}
