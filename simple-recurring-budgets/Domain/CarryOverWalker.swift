import Foundation

/// Returns the cumulative carry-over from every completed active period in the walk window.
///
/// Walk window: `[walkWindowStart, currentPeriodStart)`. For each completed period:
/// - active → contributes `allocationInEffect − sum(expenses in period)`.
/// - paused → contributes 0.
///
/// Expenses are filtered by `max(boundaryStart, walkWindowStart)` so that for the period
/// containing `walkWindowStart` (e.g., the period in which a Reset Carry-Over occurred),
/// pre-reset expenses are not counted. Allocation is still awarded for the full period —
/// no proration — matching the design choice that the user gets the full period's spending
/// power even when the budget started, or was reset, mid-period.
///
/// Backdated expenses are automatically folded in on the next call because the walker
/// re-evaluates every period on every read (pure function, no cached state).
///
/// **Contract:** `sortedAllocationChanges` and `sortedLifecycleEvents` must be pre-sorted
/// ascending by `(effectiveFrom, lastModified)` and `(effectiveDate, lastModified)`
/// respectively. The caller (`BudgetCalculator.snapshot`) sorts once at the entry point
/// to avoid an O(log N) factor per walker iteration.
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

    // Only process periods that have fully completed.
    guard nextBoundary <= currentPeriodStart else { break }

    // Paused periods contribute 0.
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
